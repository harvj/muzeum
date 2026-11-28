require "json"
require "pathname"
require "tempfile"

module MuzeumPublishedRelease
  FILENAME = "PUBLISHED_RELEASE"
  STABLE_TAG = /\Av(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/
  SHA = /\A[0-9a-f]{40}\z/

  def self.revision(path)
    raw = path.join("REVISION").binread(43)
    value = raw.strip
    value if raw.bytesize <= 42 && SHA.match?(value)
  rescue SystemCallError, IOError
    nil
  end

  def self.from_file(path, revision:)
    return unless revision && SHA.match?(revision) && path.file?

    raw = path.binread(129)
    commit, tag, extra = raw.split
    tag if raw.bytesize <= 128 && commit == revision && tag && STABLE_TAG.match?(tag) && !extra
  rescue SystemCallError, IOError
    nil
  end

  def self.verify!(revision, tag:, command:)
    raise "Expected a stable release tag and deployed SHA" unless SHA.match?(revision) && STABLE_TAG.match?(tag) && tag.bytesize <= 86

    release = JSON.parse(command.call("gh", "release", "view", tag, "--repo", "harvj/muzeum",
      "--json", "tagName,isDraft,isPrerelease,publishedAt"))
    unless release["tagName"] == tag && release["isDraft"] == false && release["isPrerelease"] == false &&
        release["publishedAt"].is_a?(String) && !release["publishedAt"].empty?
      raise "Expected a published stable Muzeum release"
    end

    target = command.call("gh", "api", "repos/harvj/muzeum/commits/#{tag}", "--jq", ".sha")
    raise "Published release tag does not match the deployed SHA" unless target == revision

    tag
  end

  def self.synchronize!(root, revision, tag)
    raise "Invalid release metadata" unless SHA.match?(revision) && STABLE_TAG.match?(tag) && tag.bytesize <= 86

    shared = root.join("shared")
    current = root.join("current")
    File.open(shared.join(".release-metadata.lock"), File::RDWR | File::CREAT, 0o600) do |lock|
      lock.flock(File::LOCK_EX)
      Tempfile.create(".published-release", shared) do |staged|
        staged.write("#{revision} #{tag}\n")
        staged.flush
        # The setgid shared directory gives the marker the Muzeum runtime group.
        staged.chmod(0o640)
        staged.fsync
        raise "Deployed SHA changed during release verification" unless self.revision(current) == revision

        File.rename(staged.path, shared.join(FILENAME))
        File.open(shared, &:fsync)
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  revision, tag = ARGV
  release = Pathname(__FILE__).realpath.dirname.parent
  MuzeumPublishedRelease.synchronize!(release.parent.parent, revision.to_s, tag.to_s)
end
