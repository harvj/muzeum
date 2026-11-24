require "json"
require "open3"

module MuzeumDeploymentRevision
  VERSION = /\Av(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/
  SHA = /\A[0-9a-f]{40}\z/
  RELEASES = File.expand_path("../config/deploy/releases.json", __dir__)

  def self.command(*arguments, raw: false)
    output, _errors, status = Open3.capture3({ "GIT_TERMINAL_PROMPT" => "0", "GH_PROMPT_DISABLED" => "true", "GIT_SSH_COMMAND" => "ssh -o BatchMode=yes -o StrictHostKeyChecking=yes" }, *arguments)
    raise "Deployment preflight command failed: #{arguments.first}" unless status.success?
    raw ? output : output.strip
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

  def self.ci!(sha, branch: nil)
    runs = JSON.parse(command("gh", "run", "list", "--repo", "harvj/muzeum", "--commit", sha,
      "--workflow", "CI", "--limit", "1", "--json", "headSha,headBranch,event,status,conclusion,url",
      *([ "--branch", branch, "--event", "push" ] if branch)))
    run = runs.first
    raise "Latest CI run for exact SHA must pass" unless run && run["headSha"] == sha && run["status"] == "completed" && run["conclusion"] == "success"
    raise "Release CI must come from the selected branch push" if branch && (run["headBranch"] != branch || run["event"] != "push")
    run.fetch("url")
  end

  def self.resolve!
    sha = checkout!("main")
    { sha: sha, ci: ci!(sha) }
  end

  def self.resolve_release!(version, checkout)
    raise "Expected a stable vX.Y.Z release version" unless VERSION.match?(version.to_s)
    checkout!("main")
    raise "Release checkout path is required" if checkout.to_s.empty?

    review = JSON.parse(File.read(RELEASES)).fetch(version) { raise "Release version is not reviewed" }
    sha, baseline, scope = review.values_at("sha", "baseline", "scope")
    unless SHA.match?(sha.to_s) && SHA.match?(baseline.to_s) && sha != baseline &&
        scope.is_a?(String) && scope.match?(%r{\Ahttps://github\.com/harvj/muzeum/issues/\d+\#issuecomment-\d+\z})
      raise "Release requires a pinned SHA, production baseline and reviewed scope record"
    end

    branch = "release/#{version}"
    # The release worktree must retain the same approved repository and track its own upstream.
    Dir.chdir(File.realpath(checkout)) do
      raise "Release checkout does not match reviewed SHA" unless checkout!(branch) == sha
      command("git", "merge-base", "--is-ancestor", baseline, sha)
    end
    { sha:, ci: ci!(sha, branch:), branch:, version:, baseline:, scope: }
  end
end
