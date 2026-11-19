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
  SHADOW_BOUNDS = { opacity_percent: 0..100, blur_px: 0..8, x_px: -4..4, y_px: -4..4 }.freeze
  BACKING_BOUNDS = { opacity_percent: 0..50 }.freeze
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
        manifest["schema_version"] == 1 && manifest["commit"].is_a?(String) && manifest["release"].is_a?(String) &&
        /\A[0-9a-f]{40}\z/.match?(manifest["commit"]) &&
        SHA_PATTERN.match?(manifest["release"]) && manifest["assets"].is_a?(Hash)
      raise InvalidManifest
    end

    assets = manifest.fetch("assets")
    IDS.each_with_object({ release: manifest.fetch("release").freeze }) do |(slot, id), snapshot|
      record = assets[id]
      next unless valid_record?(record)

      snapshot[slot] = if slot == :favicon
        record.fetch("url").freeze
      else
        background_record(record)
      end
    end.freeze
  end

  def background_record(record)
    result = record.slice("url")
    result["foreground"] = record["foreground"] if %w[light dark].include?(record["foreground"])
    if (presentation = record["presentation"]).is_a?(Hash)
      treatment = valid_treatment_fields(presentation)
      if (regions = presentation["regions"]).is_a?(Hash)
        overrides = regions.slice(*REGIONS).transform_values { |region| valid_treatment_fields(region) }
        overrides.reject! { |_, region| region.empty? }
        treatment["regions"] = overrides if overrides.any?
      end
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

    match = URL_PATTERN.match(record["url"])
    match && match[1] == record["sha256"] &&
      MEDIA_TYPES.key?(match[2]) && MEDIA_TYPES[match[2]] == record["media_type"] &&
      integral_in_range?(record["bytes"], 1..(25 * 1024 * 1024)) &&
      record["rights"].is_a?(String) && !record["rights"].empty?
  end

  def valid_treatment_fields(treatment)
    return {} unless treatment.is_a?(Hash)

    treatment.slice("foreground", "text_shadow", "backing").select do |key, value|
      case key
      when "foreground" then valid_color?(value)
      when "text_shadow" then valid_effect?(value, SHADOW_BOUNDS)
      when "backing" then valid_effect?(value, BACKING_BOUNDS)
      end
    end
  end

  def valid_effect?(value, bounds)
    value.is_a?(Hash) && value.keys.sort == [ "color", *bounds.keys.map(&:to_s) ].sort &&
      valid_color?(value["color"]) && bounds.all? { |name, range| integral_in_range?(value[name.to_s], range) }
  end

  def integral_in_range?(value, range)
    value.is_a?(Numeric) && range.cover?(value) && value % 1 == 0
  end

  def valid_color?(value)
    value.is_a?(String) && COLOR_PATTERN.match?(value)
  end

  CACHE = new
  private_constant :CACHE
end
