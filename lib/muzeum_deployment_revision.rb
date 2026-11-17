require "json"
require "open3"

module MuzeumDeploymentRevision
  def self.command(*arguments)
    output, _errors, status = Open3.capture3({ "GIT_TERMINAL_PROMPT" => "0", "GH_PROMPT_DISABLED" => "true", "GIT_SSH_COMMAND" => "ssh -o BatchMode=yes -o StrictHostKeyChecking=yes" }, *arguments)
    raise "Deployment preflight command failed: #{arguments.first}" unless status.success?
    output.strip
  end

  def self.resolve!
    raise "Deployment requires a clean checkout (including untracked files)" unless command("git", "status", "--porcelain").empty?
    raise "Routine deployment requires local main" unless command("git", "symbolic-ref", "--short", "HEAD") == "main"
    upstream = command("git", "rev-parse", "--symbolic-full-name", "@{upstream}")
    raise "main must track origin/main" unless upstream == "refs/remotes/origin/main"
    remote = command("git", "remote", "get-url", "origin")
    raise "Unexpected production repository" unless [ "git@github.com:harvj/muzeum.git", "https://github.com/harvj/muzeum.git" ].include?(remote)
    command("git", "fetch", "--no-tags", "origin", "main")
    sha = command("git", "rev-parse", "HEAD")
    raise "Immutable commit required" unless sha.match?(/\A[0-9a-f]{40}\z/) && command("git", "cat-file", "-t", sha) == "commit"
    raise "Local main must equal origin/main; ahead, behind and diverged checkouts are refused" unless command("git", "rev-parse", "origin/main") == sha
    runs = JSON.parse(command("gh", "run", "list", "--repo", "harvj/muzeum", "--commit", sha,
      "--workflow", "CI", "--limit", "1", "--json", "headSha,status,conclusion,url"))
    run = runs.first
    raise "Latest CI run for exact SHA must pass" unless run && run["headSha"] == sha && run["status"] == "completed" && run["conclusion"] == "success"
    { sha: sha, ci: run.fetch("url") }
  end
end
