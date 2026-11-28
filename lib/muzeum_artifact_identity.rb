require "digest"
require "json"
require "time"
require "thread"

# Read the exact-artifact records exported by the trusted release workflow.
# Page rendering performs local reads only.
class MuzeumArtifactIdentity
  VERSION = /\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/
  SOURCE = /\A[0-9a-f]{40}\z/
  DIGEST = /\A[0-9a-f]{64}\z/
  CANDIDATE_KEYS = %w[application artifact_sha256 candidate_number kind schema_version source_sha target_version].freeze
  PUBLICATION_KEYS = %w[acceptance_ref accepted_at candidate final_version kind publication_ref published_at schema_version verified_at].freeze

  def self.boot(release, revision:, receipts:)
    candidate = read(release.join("ARTIFACT_IDENTITY.json"))
    new(candidate, receipts) if candidate?(candidate, revision)
  end

  def self.candidate?(candidate, revision)
    candidate.is_a?(Hash) && candidate.keys.sort == CANDIDATE_KEYS &&
      candidate.values_at("schema_version", "application", "kind", "source_sha") == [ 1, "muzeum", "candidate", revision ] &&
      revision.is_a?(String) && SOURCE.match?(revision) &&
      candidate["target_version"].is_a?(String) && VERSION.match?(candidate["target_version"]) &&
      candidate["artifact_sha256"].is_a?(String) && DIGEST.match?(candidate["artifact_sha256"]) &&
      candidate["candidate_number"].is_a?(Integer) && candidate["candidate_number"].positive?
  end

  def self.read(path)
    return unless path.lstat.file? && (path.stat.mode & 0o022).zero?

    raw = path.binread(8193)
    return if raw.bytesize > 8192

    parsed = JSON.parse(raw, allow_duplicate_key: false)
    parsed if parsed.is_a?(Hash)
  rescue SystemCallError, IOError, JSON::ParserError
    nil
  end

  def self.receipt?(record, candidate, now: Time.now)
    return false unless record&.keys&.sort == PUBLICATION_KEYS
    return false unless record.values_at("schema_version", "kind", "candidate", "final_version") ==
      [ 1, "publication", candidate, "v#{candidate.fetch('target_version')}" ]
    return false unless record.values_at("acceptance_ref", "publication_ref").all? { |ref| ref.is_a?(String) && !ref.strip.empty? }

    accepted, published, verified = record.values_at("accepted_at", "published_at", "verified_at").map { |time| Time.iso8601(time) }
    accepted <= published && published <= verified && verified <= now
  rescue ArgumentError, TypeError
    false
  end

  def initialize(candidate, receipts)
    @candidate = candidate.freeze
    @label = "v#{candidate.fetch('target_version')}-rc.#{candidate.fetch('candidate_number')}".freeze
    digest = Digest::SHA256.hexdigest(candidate.sort.to_h.to_json)
    @receipt = receipts.join("#{digest}.json")
    @mutex = Mutex.new
  end

  def label
    @mutex.synchronize do
      @published ||= "v#{@candidate.fetch('target_version')}" if verified_publication?
      @published || @label
    end
  end

  private

  def verified_publication?
    self.class.receipt?(self.class.read(@receipt), @candidate)
  end
end
