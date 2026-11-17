require "json"
require "open3"
require "fileutils"
require "time"
require "timeout"

# Operator-side outbox only. No GitHub credential or reporting code runs on production.
module MuzeumDeploymentReporting
  class Error < StandardError; end

  class Github
    def call(method, path, body = nil)
      arguments = [ "gh", "api", "--method", method, "-H", "Accept: application/vnd.github+json", path ]
      arguments += [ "--input", "-" ] if body
      output = nil
      Open3.popen3({ "GH_PROMPT_DISABLED" => "true" }, *arguments, pgroup: true) do |input, stdout, stderr, wait|
        readers = [ Thread.new { stdout.read }, Thread.new { stderr.read } ]
        input.write(body ? JSON.generate(body) : "")
        input.close
        begin
          status = Timeout.timeout(30) { wait.value }
        rescue Timeout::Error
          Process.kill("KILL", -wait.pid) rescue nil
          wait.value
          raise Error, "GitHub reporting timed out; nonsecret outbox retained"
        ensure
          readers.each(&:join)
        end
        raise Error, "GitHub reporting unavailable; nonsecret outbox retained" unless status.success?
        output = readers.first.value
      end
      JSON.parse(output)
    rescue JSON::ParserError, SystemCallError
      raise Error, "GitHub response unavailable; nonsecret outbox retained"
    end
  end

  class Outbox
    REPOSITORY = "repos/harvj/muzeum"
    TERMINAL = %w[success failure error inactive].freeze

    def initialize(root, api: Github.new)
      @root, @api = File.expand_path(root), api
      FileUtils.mkdir_p(@root, mode: 0o700)
    end

    def synchronize
      File.open(File.join(@root, "reporting.lock"), File::RDWR | File::CREAT, 0o600) do |lock|
        raise Error, "Another local reporting operation is running" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        yield
      end
    end

    def check_clear!
      synchronize do
        pending = Dir.glob(File.join(@root, "*.json")).any? { |path| !JSON.parse(File.read(path))["reported"] }
        raise Error, "Resolve the pending GitHub outbox before another deployment (muzeum:report[TOKEN])" if pending
      end
    end

    def create(sha, token)
      identity!(sha, token)
      synchronize do
        pending = Dir.glob(File.join(@root, "*.json")).any? { |path| !JSON.parse(File.read(path))["reported"] }
        raise Error, "Resolve the pending GitHub outbox before another deployment (muzeum:report[TOKEN])" if pending
        record = { "sha" => sha, "token" => token, "creation" => "new", "phase" => "initiating", "desired" => "in_progress", "reported" => false }
        save(record)
      end
    end

    def start(token)
      synchronize { publish(load(token)) }
    end

    def attempted(token)
      synchronize do
        record = load(token)
        record["attempted"] = true
        record["reported"] = false
        save(record)
      end
    end

    def reconcile(token, receipt)
      synchronize do
        record = load(token)
        identity!(receipt.fetch("sha"), receipt.fetch("token"))
        raise Error, "Server receipt identity mismatch" unless receipt["sha"] == record["sha"] && receipt["token"] == token
        state = case receipt.fetch("phase")
        when "complete"
          raise Error, "Server verification is incomplete" unless receipt["health"] == "passed"
          "success"
        when "cancelled" then "error"
        when "failed" then record["attempted"] ? "failure" : "error"
        else "in_progress"
        end
        if TERMINAL.include?(record["desired"]) && record["desired"] != state
          raise Error, "Conflicting terminal result requires operator inspection"
        end
        record["phase"] = receipt.fetch("phase")
        record["desired"] = state
        record["reported"] = false
        save(record) # Actual result is durable BEFORE any GitHub request.
        publish(record)
      end
    end

    def read(token)
      load(token)
    end

    private

    def identity!(sha, token)
      raise Error, "Invalid reporting identity" unless sha.to_s.match?(/\A[0-9a-f]{40}\z/) && token.to_s.match?(/\A[0-9a-f]{32}\z/)
    end

    def load(token)
      raise Error, "Invalid reporting token" unless token.to_s.match?(/\A[0-9a-f]{32}\z/)
      record = JSON.parse(File.read(File.join(@root, "#{token}.json")))
      identity!(record["sha"], record["token"])
      raise Error, "Outbox token mismatch" unless record["token"] == token
      record
    end

    def save(record)
      path = File.join(@root, "#{record.fetch('token')}.json")
      File.open(path + ".tmp", File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |file|
        file.write(JSON.pretty_generate(record) + "\n")
        file.flush
        file.fsync
      end
      File.rename(path + ".tmp", path)
    end

    def find_deployment(record)
      matches = []
      page = 1
      loop do
        rows = @api.call("GET", "#{REPOSITORY}/deployments?sha=#{record.fetch('sha')}&environment=production&task=deploy&per_page=100&page=#{page}")
        matches.concat(rows.select { |row| row["payload"].is_a?(Hash) && row["payload"]["muzeum_token"] == record["token"] })
        break if rows.size < 100
        page += 1
      end
      raise Error, "Duplicate GitHub records require operator inspection" if matches.size > 1
      matches.first
    end

    def deployment(record)
      row = if record["deployment_id"]
        @api.call("GET", "#{REPOSITORY}/deployments/#{record.fetch('deployment_id')}")
      else
        find_deployment(record)
      end
      unless row
        # GitHub has no create idempotency key. After an ambiguous POST, lookup ONLY.
        # Never send a second create that could race visibility of the first response.
        raise Error, "Ambiguous GitHub creation; retry lookup later or reconcile manually; no duplicate created" unless record["creation"] == "new"
        record["creation"] = "posting"
        save(record)
        row = @api.call("POST", "#{REPOSITORY}/deployments", {
          ref: record.fetch("sha"), task: "deploy", environment: "production", auto_merge: false,
          required_contexts: [], production_environment: true, transient_environment: false,
          description: "Operator Capistrano attempt #{record.fetch('token')}",
          payload: { muzeum_token: record.fetch("token"), receipt: "#{record.fetch('token')}.json", driver: "local-capistrano" }
        })
      end
      unless row["id"].is_a?(Integer) && row["sha"] == record["sha"] && row["environment"] == "production" && row.dig("payload", "muzeum_token") == record["token"]
        raise Error, "GitHub deployment identity mismatch"
      end
      record["deployment_id"] = row.fetch("id")
      record["creation"] = "confirmed"
      save(record)
      row.fetch("id")
    end

    def publish(record)
      id = deployment(record)
      latest = @api.call("GET", "#{REPOSITORY}/deployments/#{id}/statuses?per_page=1").first
      if latest && TERMINAL.include?(latest["state"]) && latest["state"] != record["desired"]
        raise Error, "Conflicting GitHub terminal status; no contradictory update sent"
      end
      unless latest && latest["state"] == record["desired"]
        verification = record["desired"] == "success" ? "verified service, schema and worker health" : "#{record.fetch('phase')}; inspect receipt"
        @api.call("POST", "#{REPOSITORY}/deployments/#{id}/statuses", {
          state: record.fetch("desired"), environment: "production", environment_url: "https://muzeum.fm",
          auto_inactive: false, description: "#{record.fetch('sha')[0, 12]} #{verification}"[0, 140]
        })
      end
      record["reported"] = TERMINAL.include?(record["desired"])
      record["published_state"] = record.fetch("desired")
      record["published_at"] = Time.now.utc.iso8601
      save(record)
      { id: id, state: record.fetch("desired"), terminal: record.fetch("reported") }
    end
  end
end
