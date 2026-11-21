require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../lib/muzeum_deployment_revision"

RSpec.describe MuzeumDeploymentRevision do
  def git(*arguments)
    described_class.command("git", *arguments)
  end

  around do |example|
    Dir.mktmpdir("muzeum-deployment-git") do |root|
      Dir.chdir(root) do
        system("git", "init", "--bare", "--initial-branch=main", "remote.git", out: File::NULL, err: File::NULL, exception: true)
        system("git", "clone", "remote.git", "checkout", out: File::NULL, err: File::NULL, exception: true)
        Dir.chdir("checkout") do
          git("config", "user.email", "fixture@example.test")
          git("config", "user.name", "Deployment fixture")
          File.write("fixture", "approved\n")
          git("add", "fixture")
          git("commit", "-m", "Approved fixture")
          git("push", "-u", "origin", "main")
          @sha = git("rev-parse", "HEAD")
          @ci = { "headSha" => @sha, "status" => "completed", "conclusion" => "success", "url" => "https://example.test/fixture-ci" }
          example.run
        end
      end
    end
  end

  before do
    allow(described_class).to receive(:command).and_wrap_original do |original, *arguments|
      if arguments == [ "git", "remote", "get-url", "origin" ]
        "git@github.com:harvj/muzeum.git"
      elsif arguments.first == "gh"
        JSON.generate([ @ci ])
      else
        original.call(*arguments)
      end
    end
  end

  it "pins a clean synchronized commit after fetching its remote and passing exact CI" do
    expect(described_class.resolve!).to eq(sha: @sha, ci: @ci["url"])
  end

  it "refuses untracked and tracked dirty files" do
    File.write("untracked", "unreviewed")
    expect { described_class.resolve! }.to raise_error(/clean checkout/)
    File.delete("untracked")
    File.write("fixture", "modified")
    expect { described_class.resolve! }.to raise_error(/clean checkout/)
  end

  it "refuses a clean local commit ahead of the remote" do
    File.write("fixture", "unpublished")
    git("commit", "-am", "Not pushed")
    expect { described_class.resolve! }.to raise_error(/equal origin\/main/)
  end

  it "fetches and refuses a remote ahead of the local checkout" do
    File.write("fixture", "remote update")
    git("commit", "-am", "New remote")
    git("push")
    git("reset", "--hard", @sha)
    expect { described_class.resolve! }.to raise_error(/equal origin\/main/)
  end

  it "refuses diverged history" do
    File.write("fixture", "remote update")
    git("commit", "-am", "Remote history")
    git("push")
    git("reset", "--hard", @sha)
    File.write("fixture", "different local update")
    git("commit", "-am", "Diverged local history")
    expect { described_class.resolve! }.to raise_error(/equal origin\/main/)
  end

  it "refuses detached or alternate branches and incorrect upstreams" do
    git("checkout", "--detach")
    expect { described_class.resolve! }.to raise_error(/preflight command failed/)
    git("checkout", "main")
    git("branch", "--unset-upstream")
    expect { described_class.resolve! }.to raise_error(/preflight command failed/)
  end

  it "refuses failed, pending, missing and mismatched CI evidence" do
    [ { "conclusion" => "failure" }, { "status" => "in_progress" }, { "headSha" => "0" * 40 } ].each do |change|
      original = @ci.dup
      @ci.merge!(change)
      expect { described_class.resolve! }.to raise_error(/exact SHA must pass/)
      @ci = original
    end
    @ci = {}
    expect { described_class.resolve! }.to raise_error(/exact SHA must pass/)
  end

  context "with a separate release checkout" do
    let(:version) { "v0.3.2" }
    let(:branch) { "release/#{version}" }
    let(:scope) { "https://github.com/harvj/muzeum/issues/32#issuecomment-123" }
    let(:release_checkout) { File.expand_path("../release") }
    let(:manifest) { File.expand_path("../releases.json") }

    before do
      git("worktree", "add", "-b", branch, release_checkout, @sha)
      Dir.chdir(release_checkout) do
        File.write("fixture", "release candidate\n")
        git("commit", "-am", "Release candidate")
        git("push", "-u", "origin", branch)
        @candidate = git("rev-parse", "HEAD")
      end
      @ci.merge!("headSha" => @candidate, "headBranch" => branch, "event" => "push")
      stub_const("MuzeumDeploymentRevision::RELEASES", manifest)
      write_review
    end

    def write_review(override = {})
      File.write(manifest, JSON.generate(version => { sha: @candidate, baseline: @sha, scope: }.merge(override)))
    end

    it "requires an explicit reviewed release and pins its separate CI and baseline" do
      expect(described_class.resolve_release!(version, release_checkout)).to eq(
        sha: @candidate, baseline: @sha, branch:, version:, scope:, ci: @ci["url"]
      )
      Dir.chdir(release_checkout) do
        expect { described_class.resolve! }.to raise_error(/requires local main/)
      end
    end

    it "rejects arbitrary branches and unapproved versions" do
      expect { described_class.resolve_release!("main", release_checkout) }.to raise_error(/stable vX.Y.Z/)
      expect { described_class.resolve_release!("v0.3.3", release_checkout) }.to raise_error(/not reviewed/)
      expect { described_class.resolve_release!(version, Dir.pwd) }.to raise_error(/requires local release/)
    end

    it "rejects a dirty release checkout and a reviewed SHA mismatch" do
      dirty = File.join(release_checkout, "untracked")
      File.write(dirty, "unreviewed")
      expect { described_class.resolve_release!(version, release_checkout) }.to raise_error(/clean checkout/)
      File.delete(dirty)
      write_review(sha: "0" * 40)
      expect { described_class.resolve_release!(version, release_checkout) }.to raise_error(/reviewed SHA/)
    end

    it "rejects a missing baseline and absent or cross-branch CI" do
      write_review(baseline: "0" * 40)
      expect { described_class.resolve_release!(version, release_checkout) }.to raise_error(/preflight command failed/)
      write_review
      @ci["headBranch"] = "main"
      expect { described_class.resolve_release!(version, release_checkout) }.to raise_error(/selected branch push/)
      @ci = {}
      expect { described_class.resolve_release!(version, release_checkout) }.to raise_error(/exact SHA must pass/)
    end
  end
  context "with the pinned v0.3.4 exception" do
    let(:version) { "v0.3.4" }
    let(:controls) { "controls/v0.3.4-shell" }
    let(:candidate_branch) { "candidate/v0.3.4-shell-revocation" }
    let(:release) { "release/v0.3.4" }
    let(:release_checkout) { File.expand_path("../release") }
    let(:manifest) { File.expand_path("../releases.json") }

    before do
      git("worktree", "add", "-b", release, release_checkout, @sha)
      Dir.chdir(release_checkout) do
        File.write("fixture", "forward\n")
        git("commit", "-am", "Pinned forward candidate")
        git("push", "-u", "origin", release)
        @candidate = git("rev-parse", "HEAD")
      end
      git("switch", "-c", controls)
      File.write("fixture", "controls\n")
      git("commit", "-am", "Reviewed controls")
      git("push", "-u", "origin", controls)
      @control_sha = git("rev-parse", "HEAD")
      stub_const("MuzeumDeploymentRevision::V034_SHA", @candidate)
      stub_const("MuzeumDeploymentRevision::RELEASES", manifest)
      File.write(manifest, JSON.generate(version => { sha: @candidate, baseline: @sha,
        scope: "https://github.com/harvj/muzeum/issues/28#issuecomment-123" }))
      @job_rows = described_class::REQUIRED_JOBS.map { |name| { name:, status: "completed", conclusion: "success" } }
      @forward_run = { databaseId: 2, headSha: @candidate, headBranch: candidate_branch, event: "push",
        status: "completed", conclusion: "success", url: "https://example.test/forward-ci" }
      @control_run = @forward_run.merge(databaseId: 1, headSha: @control_sha, headBranch: controls)
      allow(described_class).to receive(:command).and_wrap_original do |original, *arguments|
        case arguments
        when %w[git remote get-url origin]
          "git@github.com:harvj/muzeum.git"
        when ->(args) { args.take(3) == %w[gh run list] }
          run = arguments.include?(controls) ? @control_run : @forward_run
          expect(arguments).to include("--commit", "--branch", run.equal?(@control_run) ? controls : candidate_branch, "--event", "push")
          JSON.generate([ run ])
        when ->(args) { args.take(3) == %w[gh run view] }
          run = arguments.fetch(3) == "1" ? @control_run : @forward_run
          JSON.generate(run.merge(jobs: @job_rows))
        else
          original.call(*arguments)
        end
      end
    end

    it "keeps the approved release checkout while verifying candidate push CI and control push CI" do
      result = described_class.resolve_release!(version, release_checkout)
      expect(result).to include(sha: @candidate, branch: release, ci: @forward_run[:url])
    end

    it "rejects missing and failed required jobs even when the run reports success" do
      missing = @job_rows.pop
      expect { described_class.resolve_release!(version, release_checkout) }.to raise_error(/Required CI jobs/)
      @job_rows << missing.merge(conclusion: "failure")
      expect { described_class.resolve_release!(version, release_checkout) }.to raise_error(/Required CI jobs/)
    end

    it "rejects a modified v0.3.4 review SHA" do
      review = JSON.parse(File.read(manifest))
      review.fetch(version)["sha"] = @control_sha
      File.write(manifest, JSON.generate(review))
      expect { described_class.resolve_release!(version, release_checkout) }.to raise_error(/pinned forward SHA/)
    end

    it "rejects an unrelated forward CI branch and an unauthorized control branch" do
      @forward_run[:headBranch] = release
      expect { described_class.resolve_release!(version, release_checkout) }.to raise_error(/selected branch push/)
      git("switch", "main")
      expect { described_class.resolve_release!(version, release_checkout) }.to raise_error(/requires local controls/)
    end
  end

  it "pins the hotfix and verifies CI for both hotfix branches" do
    hotfix = described_class::V035_SHA
    baseline = described_class::V034_SHA
    controls = "b" * 40
    release_branch = "release/v0.3.5"
    control_branch = "controls/v0.3.5"
    allow(described_class).to receive(:checkout!).with(control_branch).and_return(controls)
    allow(described_class).to receive(:checkout!).with(release_branch).and_return(hotfix)
    expect(described_class).to receive(:ci!).with(controls, branch: control_branch, required_jobs: true).ordered
    expect(described_class).to receive(:command).with("git", "merge-base", "--is-ancestor", baseline, hotfix).and_return("")
    expect(described_class).to receive(:ci!).with(hotfix, branch: release_branch, required_jobs: true).ordered.and_return("https://example.test/ci")

    expect(described_class.resolve_release!("v0.3.5", Dir.pwd)).to include(sha: hotfix, baseline:, branch: release_branch)
    expect(described_class.patched_runtime?(baseline)).to be(true)
  end
end
