class ApplicationShellRegistry
  MAX_BYTES = 64.kilobytes
  VERSION = /\A1\.1\.(?:0|[1-9][0-9]*)\z/
  DIGEST = /\A[0-9a-f]{64}\z/
  ROOT_URL = %r{\Ahttps://[a-z0-9]+(?:[.-][a-z0-9]+)+/\z}
  ENTRY_KEYS = %w[availability canonical_url id name].freeze
  EXCLUDED_IDS = %w[auth infrastructure site-art].freeze
  EXCLUDED_HOSTS = %w[auth.harvj.com infrastructure.harvj.com art.harvj.com site-art.harvj.com
    network.harvj.com intelligence.harvj.com radioactivita.com pandemic.radioactivita.com modernart.radioactivita.com].freeze

  def self.destinations(eligible, path: ENV["MUZEUM_SHELL_REGISTRY_CACHE"])
    return [] if path.blank?

    File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |file|
      stat = file.stat
      return [] unless stat.file? && (stat.mode & 0o022).zero?

      bytes = file.read(MAX_BYTES + 1)
      return [] if bytes.bytesize > MAX_BYTES

      entries = verified_entries(JSON.parse(bytes, allow_duplicate_key: false))
      entries.filter_map do |entry|
        next unless entry["id"] != "muzeum" && entry["availability"] == "production" && eligible.include?(entry["id"])

        { name: entry.fetch("name"), url: entry.fetch("canonical_url") }
      end
    end
  rescue SystemCallError, JSON::ParserError, IOError
    []
  end

  def self.verified_entries(envelope)
    return [] unless envelope.is_a?(Hash) && envelope["format_version"].eql?(1) &&
      VERSION.match?(envelope["specification_version"].to_s) && envelope["sequence"].is_a?(Integer) && envelope["sequence"].positive? &&
      %w[manifest_sha256 pointer_sha256 registry_sha256].all? { |key| DIGEST.match?(envelope[key].to_s) }

    raw = envelope["registry_json"]
    return [] unless raw.is_a?(String) && Digest::SHA256.hexdigest(raw) == envelope["registry_sha256"]

    registry = JSON.parse(raw, allow_duplicate_key: false)
    return [] unless registry.is_a?(Hash) && registry == envelope["registry"] &&
      registry["schema_version"].eql?(1) && registry["specification_version"] == envelope["specification_version"]

    entries = registry["applications"]
    return [] unless entries.is_a?(Array) && entries.all? { |entry| valid_entry?(entry) }
    return [] unless %w[id canonical_url].all? { |key| entries.map { |entry| entry[key] }.uniq.size == entries.size }

    entries
  end

  def self.valid_entry?(entry)
    return false unless entry.is_a?(Hash) && entry.keys.sort == ENTRY_KEYS &&
      entry["id"].is_a?(String) && ApplicationShellEvidence::DESTINATION.match?(entry["id"]) &&
      entry["name"].is_a?(String) && entry["name"].present? &&
      entry["availability"].in?(%w[production withdrawn]) &&
      entry["canonical_url"].is_a?(String) && ROOT_URL.match?(entry["canonical_url"])

    host = URI(entry["canonical_url"]).host
    !EXCLUDED_IDS.include?(entry["id"]) && !EXCLUDED_HOSTS.include?(host) && !host.match?(/staging|preview/)
  end
end
