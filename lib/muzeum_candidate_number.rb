require "json"
require "tempfile"
require_relative "muzeum_artifact_identity"

# Called by the release packager in its deploy-owned persistent directory.
class MuzeumCandidateNumber
  def self.allocate(directory, version:, revision:, artifact_sha256:)
    unless MuzeumArtifactIdentity::VERSION.match?(version) &&
        MuzeumArtifactIdentity::SOURCE.match?(revision) &&
        MuzeumArtifactIdentity::DIGEST.match?(artifact_sha256)
      raise ArgumentError, "Invalid release candidate identity"
    end

    ledger = directory.join("#{version}.json")
    File.open(directory.join("#{version}.lock"), File::RDWR | File::CREAT | File::NOFOLLOW, 0o600) do |lock|
      lock.flock(File::LOCK_EX)
      entries = read(ledger)
      identity = [ revision, artifact_sha256 ]
      existing = entries.index(identity)
      return existing + 1 if existing

      entries << identity
      Tempfile.create(".candidate-", directory) do |file|
        file.write(JSON.generate(entries))
        file.flush
        file.fsync
        File.rename(file.path, ledger)
        File.open(directory) { |parent| parent.fsync }
      end
      entries.size
    end
  end

  def self.read(ledger)
    raw = File.open(ledger, File::RDONLY | File::NOFOLLOW, &:read)
    entries = JSON.parse(raw)
    unless entries.is_a?(Array) && entries.uniq == entries && entries.all? { |entry|
      entry.is_a?(Array) && entry.size == 2 &&
        MuzeumArtifactIdentity::SOURCE.match?(entry.first) && MuzeumArtifactIdentity::DIGEST.match?(entry.last)
    }
      raise "Invalid candidate numbering ledger"
    end

    entries
  rescue Errno::ENOENT
    []
  end

  private_class_method :read
end
