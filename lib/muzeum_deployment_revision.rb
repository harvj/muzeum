require "base64"
require "json"
require "open3"

module MuzeumDeploymentRevision
  VERSION = /\Av(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/
  SHA = /\A[0-9a-f]{40}\z/
  LEGACY_RUNTIME = "024ed4aecd98984c00323377389cde5a6a35d16d"
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

  def self.patched_runtime?(sha)
    SHA.match?(sha) && sha != LEGACY_RUNTIME
  end

  def self.authorization!(checkout = Dir.pwd)
    path = ENV.fetch("MUZEUM_RELEASE_AUTHORIZATION") { raise "Set MUZEUM_RELEASE_AUTHORIZATION to the signed approval envelope" }
    bytes = File.binread(path, 24_577)
    raise "Invalid release approval size" unless bytes && bytes.bytesize <= 24_576

    envelope = JSON.parse(bytes)
    approval = JSON.parse(Base64.strict_decode64(envelope.fetch("payload")))
    sha, baseline, version, branch, ci = approval.values_at("sha", "baseline", "version", "branch", "ci")
    unless approval["application"] == "muzeum" && SHA.match?(sha.to_s) && SHA.match?(baseline.to_s) &&
        VERSION.match?(version.to_s) && [ "main", "release/#{version}" ].include?(branch)
      raise "Invalid release approval identity"
    end
    Dir.chdir(File.realpath(checkout)) do
      raise "Release checkout does not match approved SHA" unless checkout!(branch) == sha

      command("git", "merge-base", "--is-ancestor", baseline, sha)
      current_ci = ci!(sha, branch:, required_jobs: true)
      raise "Release approval CI run differs from current exact-SHA evidence" unless ci == current_ci
    end
    { sha:, baseline:, version:, branch:, ci:, envelope: Base64.strict_encode64(bytes) }
  end
end
