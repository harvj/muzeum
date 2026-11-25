require "find"
require "pathname"
require "tempfile"
require_relative "muzeum_candidate_number"

# Hashes a packaged release tree, after Capistrano builds its local assets.
# Shared runtime state is represented by the link itself, never by its contents.
class MuzeumReleasePackage
  IDENTITY = "ARTIFACT_IDENTITY.json"
  LINKED_FILES = %w[.env].freeze
  LINKED_DIRECTORIES = %w[log storage tmp].freeze
  RUNTIME_LINKS = (LINKED_FILES + LINKED_DIRECTORIES).freeze
  GENERATED_FILES = %w[REVISION_TIME .bundle/config public/assets/.manifest.json assets_manifest_backup/.manifest.json].freeze

  def self.digest(release, shared:)
    RUNTIME_LINKS.each do |name|
      link = release.join(name)
      unless link.symlink? && link.readlink == shared.join(name)
        raise "Release #{name} must link to the application shared runtime path"
      end
    end

    entries = []
    Find.find(release.to_s, ignore_error: false) do |absolute|
      path = Pathname(absolute)
      relative = path.relative_path_from(release).to_s
      next if relative == "." || relative == IDENTITY

      info = path.lstat
      if info.symlink?
        target = path.readlink
        unless RUNTIME_LINKS.include?(relative) && target == shared.join(relative)
          raise "Unexpected release symlink: #{relative}"
        end
        entries << [ relative, "link", relative ]
      elsif info.directory?
        entries << [ relative, "directory" ]
      elsif info.file?
        entries << [ relative, "file", info.mode & 0o111, Digest::SHA256.file(path).hexdigest ]
      else
        raise "Unsupported release file: #{relative}"
      end
    end
    Digest::SHA256.hexdigest(JSON.generate(entries.sort_by(&:first)))
  end

  def self.record!(release, shared:, version:, revision:)
    raise "Release target differs from the packaged VERSION" unless release.join("VERSION").read.strip == version
    GENERATED_FILES.each do |name|
      path = release.join(name)
      raise "Missing or invalid staged file: #{name}" unless path.file? && !path.symlink? && path.size.positive?
    end
    unless /\A[0-9]+\z/.match?(release.join("REVISION_TIME").read.strip)
      raise "Invalid staged revision time"
    end
    raise "Release revision differs" unless release.join("REVISION").read.strip == revision

    artifact_sha256 = digest(release, shared:)
    existing = MuzeumArtifactIdentity.read(release.join(IDENTITY))
    if existing && existing.values_at("artifact_sha256", "source_sha", "target_version") != [ artifact_sha256, revision, version ]
      raise "Candidate identity has already been bound"
    end
    number = MuzeumCandidateNumber.allocate(shared.join("release-candidates"), version:, revision:, artifact_sha256:)
    identity = {
      "application" => "muzeum", "artifact_sha256" => artifact_sha256, "candidate_number" => number,
      "kind" => "candidate", "schema_version" => 1, "source_sha" => revision, "target_version" => version
    }

    Tempfile.create(".identity-", release) do |file|
      file.write(JSON.generate(identity))
      file.flush
      file.chmod(0o640)
      file.fsync
      begin
        File.link(file.path, release.join(IDENTITY))
      rescue Errno::EEXIST
        raise "Candidate identity has already been bound" unless MuzeumArtifactIdentity.read(release.join(IDENTITY)) == identity
      end
      File.open(release, &:fsync)
    end
    identity
  end
end
