require "json"
require "open3"

module MuzeumDeploymentRevision
  VERSION = /\Av(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/
  SHA = /\A[0-9a-f]{40}\z/
  RELEASES = File.expand_path("../config/deploy/releases.json", __dir__)

  V034_SHA = "641e09ec4a6de94f0043e3a7314d28674901485c"
  V034_CONTROLS = "controls/v0.3.4"
  REQUIRED_JOBS = [
    "tests", "quality (bin/rubocop)", "quality (bin/brakeman --no-pager --exit-on-warn --exit-on-error)",
    "quality (bin/bundler-audit check --update)"
  ].freeze

  def self.command(*arguments)
    output, _errors, status = Open3.capture3({ "GIT_TERMINAL_PROMPT" => "0", "GH_PROMPT_DISABLED" => "true", "GIT_SSH_COMMAND" => "ssh -o BatchMode=yes -o StrictHostKeyChecking=yes" }, *arguments)
    raise "Deployment preflight command failed: #{arguments.first}" unless status.success?
    output.strip
  end

  def self.checkout!(branch)
    raise "Deployment requires a clean checkout (including untracked files)" unless command("git", "status", "--porcelain").empty?
    raise "Deployment requires local #{branch}" unless command("git", "symbolic-ref", "--short", "HEAD") == branch
    upstream = command("git", "rev-parse", "--symbolic-full-name", "@{upstream}")
    raise "#{branch} must track origin/#{branch}" unless upstream == "refs/remotes/origin/#{branch}"
    remote = command("git", "remote", "get-url", "origin")
    raise "Unexpected production repository" unless [ "git@github.com:harvj/muzeum.git", "https://github.com/harvj/muzeum.git" ].include?(remote)
    command("git", "fetch", "--no-tags", "origin", "refs/heads/#{branch}")
    sha = command("git", "rev-parse", "HEAD")
    raise "Immutable commit required" unless SHA.match?(sha) && command("git", "cat-file", "-t", sha) == "commit"
    raise "Local #{branch} must equal origin/#{branch}; ahead, behind and diverged checkouts are refused" unless command("git", "rev-parse", "FETCH_HEAD") == sha
    sha
  end

  def self.ci!(sha, branch: nil, required_jobs: false)
    runs = JSON.parse(command("gh", "run", "list", "--repo", "harvj/muzeum", "--commit", sha,
      "--workflow", "CI", "--limit", "1", "--json", "databaseId,headSha,headBranch,event,status,conclusion,url",
      *([ "--branch", branch, "--event", "push" ] if branch)))
    run = runs.first
    raise "Latest CI run for exact SHA must pass" unless run && run["headSha"] == sha && run["status"] == "completed" && run["conclusion"] == "success"
    raise "Release CI must come from the selected branch push" if branch && (run["headBranch"] != branch || run["event"] != "push")
    if required_jobs
      id = run.fetch("databaseId").to_s
      raise "Invalid CI run ID" unless /\A[1-9][0-9]*\z/.match?(id)
      detail = JSON.parse(command("gh", "run", "view", id, "--repo", "harvj/muzeum",
        "--json", "headSha,status,conclusion,jobs"))
      jobs = detail.fetch("jobs")
      successful = jobs.select { |job| job["status"] == "completed" && job["conclusion"] == "success" }.map { |job| job["name"] }
      unless detail.values_at("headSha", "status", "conclusion") == [ sha, "completed", "success" ] &&
          (REQUIRED_JOBS - successful).empty? && jobs.all? { |job| successful.include?(job["name"]) && job["conclusion"] == "success" && job["status"] == "completed" }
        raise "Required CI jobs for exact SHA must pass"
      end
    end
    run.fetch("url")
  end

  def self.resolve!
    sha = checkout!("main")
    { sha: sha, ci: ci!(sha) }
  end

  def self.resolve_release!(version, checkout)
    raise "Expected a stable vX.Y.Z release version" unless VERSION.match?(version.to_s)
    raise "Release checkout path is required" if checkout.to_s.empty?

    review = JSON.parse(File.read(RELEASES)).fetch(version) { raise "Release version is not reviewed" }
    sha, baseline, scope = review.values_at("sha", "baseline", "scope")
    unless SHA.match?(sha.to_s) && SHA.match?(baseline.to_s) && sha != baseline &&
        scope.is_a?(String) && scope.match?(%r{\Ahttps://github\.com/harvj/muzeum/issues/\d+\#issuecomment-\d+\z})
      raise "Release requires a pinned SHA, production baseline and reviewed scope record"
    end

    use_main_ci = version == "v0.3.4" && sha == V034_SHA
    control_sha = checkout!(use_main_ci ? V034_CONTROLS : "main")
    ci!(control_sha, branch: V034_CONTROLS, required_jobs: true) if use_main_ci
    branch = "release/#{version}"
    # The release worktree must retain the same approved repository and track its own upstream.
    Dir.chdir(File.realpath(checkout)) do
      raise "Release checkout does not match reviewed SHA" unless checkout!(branch) == sha
      command("git", "merge-base", "--is-ancestor", baseline, sha)
    end
    { sha:, ci: ci!(sha, branch: use_main_ci ? "main" : branch, required_jobs: use_main_ci), branch:, version:, baseline:, scope: }
  end
end
