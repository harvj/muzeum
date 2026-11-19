require "net/http"
require "json"
require "timeout"

class SiteArt
  ORIGIN = "https://art.harvj.com".freeze
  MANIFEST = URI("#{ORIGIN}/manifest.json").freeze
  REFRESH_INTERVAL = 60
  TIMEOUT = 0.5
  MAX_MANIFEST_BYTES = 128 * 1024
  IDS = {
    light: "muzeum.background_light",
    dark: "muzeum.background_dark",
    favicon: "muzeum.favicon"
  }.freeze
  MEDIA_TYPES = {
    "svg" => "image/svg+xml", "png" => "image/png", "jpg" => "image/jpeg",
    "jpeg" => "image/jpeg", "webp" => "image/webp", "gif" => "image/gif",
    "ico" => "image/vnd.microsoft.icon"
  }.freeze
  ID_PATTERN = /\A[a-z][a-z0-9-]*\.[a-z][a-z0-9_]*\z/
  TREATMENT_KEYS = %w[foreground text_shadow backing].freeze
  REGIONS = %w[top bottom].freeze
  COLOR_PATTERN = /\A#[0-9a-fA-F]{6}\z/
  SHA_PATTERN = /\A[0-9a-f]{64}\z/
  URL_PATTERN = %r{\A#{Regexp.escape(ORIGIN)}/assets/([0-9a-f]{64})\.([a-z]+)\z}

  class InvalidManifest < StandardError; end

  def self.snapshot
    CACHE.snapshot
  end

  def initialize
    @lock = Mutex.new
    @artwork = {}.freeze
    @next_refresh = 0
  end

  def snapshot
    @lock.synchronize do
      artwork = @artwork
      if !@refreshing && monotonic_time >= @next_refresh
        @next_refresh = monotonic_time + REFRESH_INTERVAL
        begin
          @refreshing = Thread.new { refresh }
        rescue ThreadError
          # Artwork remains optional even if a thread cannot be started.
        end
      end
      artwork
    end
  end

  private

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def refresh
    result = Timeout.timeout(TIMEOUT) { fetch_manifest }
    @lock.synchronize { @artwork, @etag = result } if result
  rescue InvalidManifest, JSON::ParserError, Timeout::Error, IOError, SystemCallError,
         SocketError, OpenSSL::SSL::SSLError, Net::ProtocolError
    # Retain the last valid snapshot and retry at the next refresh interval.
  ensure
    @lock.synchronize { @refreshing = nil }
  end

  def fetch_manifest
    http = Net::HTTP.new(MANIFEST.host, MANIFEST.port, nil)
    http.use_ssl = true
    http.open_timeout = http.read_timeout = http.write_timeout = TIMEOUT
    http.max_retries = 0
    request = Net::HTTP::Get.new(MANIFEST, "Accept" => "application/json", "Accept-Encoding" => "identity")
    request["If-None-Match"] = @etag if @etag

    http.request(request) do |response|
      next unless response.is_a?(Net::HTTPOK)

      body = +""
      response.read_body do |chunk|
        body << chunk
        raise InvalidManifest if body.bytesize > MAX_MANIFEST_BYTES
      end
      return [ validate(JSON.parse(body, allow_duplicate_key: false)), response["ETag"] ]
    end
    nil
  end

  def validate(manifest)
    unless manifest.is_a?(Hash) && manifest.keys.sort == %w[assets commit release schema_version] &&
        manifest["schema_version"].eql?(1) && manifest["commit"].is_a?(String) && manifest["release"].is_a?(String) &&
        /\A[0-9a-f]{40}\z/.match?(manifest["commit"]) &&
        SHA_PATTERN.match?(manifest["release"]) && manifest["assets"].is_a?(Hash)
      raise InvalidManifest
    end

    assets = manifest.fetch("assets")
    assets.each do |id, record|
      raise InvalidManifest unless ID_PATTERN.match?(id) && valid_record?(record)
    end
    IDS.each_with_object({ release: manifest.fetch("release").freeze }) do |(slot, id), snapshot|
      record = assets[id]
      next unless record

      snapshot[slot] = if slot == :favicon
        record.fetch("url").freeze
      else
        background_record(record)
      end
    end.freeze
  end

  def background_record(record)
    result = record.slice("url", "foreground")
    if (presentation = record["presentation"])
      treatment = presentation.slice(*TREATMENT_KEYS)
      regions = presentation["regions"]&.slice(*REGIONS)&.transform_values { |region| region.slice(*TREATMENT_KEYS) }
      regions&.reject! { |_, region| region.empty? }
      treatment["regions"] = regions if regions&.any?
      result["presentation"] = treatment if treatment.any?
    end
    freeze_value(result)
  end

  def freeze_value(value)
    value.each_value { |child| freeze_value(child) } if value.is_a?(Hash)
    value.freeze
  end

  def valid_record?(record)
    return false unless record.is_a?(Hash) && record["url"].is_a?(String)

    keys = record.keys - %w[foreground presentation]
    return false unless keys.sort == %w[bytes media_type rights sha256 url]

    match = URL_PATTERN.match(record["url"])
    match && match[1] == record["sha256"] &&
      MEDIA_TYPES.key?(match[2]) && MEDIA_TYPES.fetch(match[2]) == record["media_type"] &&
      record["bytes"].is_a?(Integer) && record["bytes"].between?(1, 25 * 1024 * 1024) &&
      record["rights"].is_a?(String) && !record["rights"].empty? &&
      (!record.key?("foreground") || %w[light dark].include?(record["foreground"])) &&
      (!record.key?("presentation") || valid_presentation?(record["presentation"]))
  end

  def valid_presentation?(presentation)
    return false unless valid_treatment?(presentation)
    return true unless presentation.key?("regions")

    regions = presentation["regions"]
    regions.is_a?(Hash) && regions.any? && regions.slice(*REGIONS).values.all? { |region| valid_treatment?(region) }
  end

  def valid_treatment?(treatment)
    return false unless treatment.is_a?(Hash) && treatment.any?

    treatment.slice(*TREATMENT_KEYS).all? do |key, value|
      case key
      when "foreground" then valid_color?(value)
      when "text_shadow"
        valid_effect?(value, opacity_percent: 0..60, blur_px: 0..8, x_px: -4..4, y_px: -4..4)
      when "backing"
        valid_effect?(value, opacity_percent: 0..50)
      end
    end
  end

  def valid_effect?(value, **bounds)
    value.is_a?(Hash) && value.keys.sort == [ "color", *bounds.keys.map(&:to_s) ].sort &&
      valid_color?(value["color"]) && bounds.all? do |name, range|
        amount = value[name.to_s]
        amount.is_a?(Integer) && range.cover?(amount)
      end
  end

  def valid_color?(value)
    value.is_a?(String) && COLOR_PATTERN.match?(value)
  end

  CACHE = new
  private_constant :CACHE
end
