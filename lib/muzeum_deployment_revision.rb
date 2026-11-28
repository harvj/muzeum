require "json"
require "open3"

module MuzeumDeploymentRevision
  SHA = /\A[0-9a-f]{40}\z/

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
end
