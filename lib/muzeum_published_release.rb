require "json"

module MuzeumPublishedRelease
  FILENAME = "PUBLISHED_RELEASE"
  STABLE_TAG = /\Av(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/

  def self.from_file(path)
    return unless path.file?

    value = path.read.strip
    value if STABLE_TAG.match?(value)
  end

  def self.verify!(revision, command:)
    release = JSON.parse(command.call("gh", "release", "view", "--repo", "harvj/muzeum",
      "--json", "tagName,isDraft,isPrerelease,publishedAt"))
    tag = release.fetch("tagName")
    unless STABLE_TAG.match?(tag) && release["isDraft"] == false && release["isPrerelease"] == false && release["publishedAt"].is_a?(String) && !release["publishedAt"].empty?
      raise "Expected a published stable Muzeum release"
    end

    target = command.call("gh", "api", "repos/harvj/muzeum/commits/#{tag}", "--jq", ".sha")
    unless target.match?(/\A[0-9a-f]{40}\z/) && command.call("git", "merge-base", target, revision) == target
      raise "Published release tag must be included in the candidate history"
    end

    tag
  end
end
