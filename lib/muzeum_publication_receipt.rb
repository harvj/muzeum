require "tempfile"
require_relative "muzeum_artifact_identity"

class MuzeumPublicationReceipt
  REPO = "harvj/muzeum"
  ASSET = "muzeum-artifact.json"

  def self.verify!(candidate, deployment_id:, status_id:, command:, asset_command: command)
    unless [deployment_id, status_id].all? { |id| /\A[1-9]\d*\z/.match?(id.to_s) }
      raise "Expected exact GitHub deployment and status IDs"
    end

    tag = "v#{candidate.fetch('target_version')}"
    endpoint = "repos/#{REPO}/deployments/#{deployment_id}"
    deployment = JSON.parse(command.call("gh", "api", endpoint))
    status = JSON.parse(command.call("gh", "api", "#{endpoint}/statuses/#{status_id}"))
    unless deployment.fetch("sha") == candidate.fetch("source_sha") &&
        deployment.fetch("environment") == "production" && deployment.fetch("production_environment") == true &&
        deployment.fetch("payload") == candidate && status.fetch("environment") == "production" &&
        status.fetch("state") == "success" && deployment.dig("creator", "login") == status.dig("creator", "login") &&
        !status.dig("creator", "login").to_s.empty?
      raise "Production deployment acceptance does not match the exact candidate"
    end

    release = JSON.parse(command.call("gh", "api", "repos/#{REPO}/releases/tags/#{tag}"))
    published_sha = command.call("gh", "api", "repos/#{REPO}/commits/#{tag}", "--jq", ".sha")
    asset = release.fetch("assets").find { |record| record["name"] == ASSET }
    unless release.fetch("tag_name") == tag && release.fetch("draft") == false && release.fetch("prerelease") == false &&
        published_sha == candidate.fetch("source_sha") && asset&.fetch("size").to_i.between?(1, 8192)
      raise "Published GitHub release does not identify the candidate"
    end

    asset_id = Integer(asset.fetch("id"))
    raw = asset_command.call("gh", "api", "repos/#{REPO}/releases/assets/#{asset_id}", "--header", "Accept: application/octet-stream")
    unless asset.fetch("digest") == "sha256:#{Digest::SHA256.hexdigest(raw)}" &&
        JSON.parse(raw, allow_duplicate_key: false) == candidate
      raise "Release asset digest or candidate binding differs"
    end

    accepted = Time.iso8601(status.fetch("created_at"))
    published = Time.iso8601(release.fetch("published_at"))
    now = Time.now.utc
    raise "Publication did not follow verified acceptance" unless accepted <= published && published <= now

    {
      "schema_version" => 1, "kind" => "publication", "candidate" => candidate, "final_version" => tag,
      "accepted_at" => accepted.iso8601, "acceptance_ref" => "#{endpoint}/statuses/#{status_id}",
      "published_at" => published.iso8601, "publication_ref" => "repos/#{REPO}/releases/assets/#{asset_id}@#{asset.fetch('digest')}",
      "verified_at" => now.iso8601
    }
  end

  def self.write!(directory, receipt)
    candidate = receipt.fetch("candidate")
    version = candidate.fetch("target_version")
    raise "Invalid release version" unless MuzeumArtifactIdentity::VERSION.match?(version)

    key = Digest::SHA256.hexdigest(candidate.sort.to_h.to_json)
    path = directory.join("#{key}.json")
    File.open(directory.join("#{version}.lock"), File::RDWR | File::CREAT | File::NOFOLLOW, 0o640) do |lock|
      lock.flock(File::LOCK_EX)
      directory.glob("*.json").each do |previous_path|
        previous = MuzeumArtifactIdentity.read(previous_path)
        raise "Invalid retained publication receipt" unless previous
        next unless previous.fetch("final_version") == receipt.fetch("final_version")

        evidence_fields = MuzeumArtifactIdentity::PUBLICATION_KEYS - ["verified_at"]
        unless previous_path == path && previous.values_at(*evidence_fields) == receipt.values_at(*evidence_fields)
          raise "Target version already belongs to a different publication receipt"
        end
        return path
      end

      Tempfile.create(".publication-", directory) do |file|
        file.write(JSON.generate(receipt))
        file.flush
        file.chmod(0o640)
        file.fsync
        File.link(file.path, path)
        File.open(directory, &:fsync)
      end
      path
    end
  end
end
