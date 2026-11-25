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
end
