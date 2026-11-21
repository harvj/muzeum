require "base64"
require "openssl"
require "tempfile"

class ApplicationShellRegistry
  class Invalid < StandardError; end
  class UniqueObject < Hash
    def []=(key, value)
      raise Invalid if key?(key)

      super
    end
  end

  ORIGIN = "https://infrastructure.harvj.com/".freeze
  CONFIG = Rails.root.join("config/application_shell")
  STATE = Rails.root.join("storage/application-shell-registry.json")
  MAX_BYTES = 2.megabytes
  VERSION = /\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/
  ID = /\A[a-z][a-z0-9]*(?:-[a-z0-9]+)*\z/
  PAYLOADS = %w[application-shell-v1.md application-shell-registry.json application-shell-registry.schema.json
    application-shell-exceptions.json auth-application-shell-handoff.md application-shell-gate.md conformance.json].freeze
  EXCLUDED_HOSTS = %w[auth.harvj.com infrastructure.harvj.com art.harvj.com site-art.harvj.com network.harvj.com intelligence.harvj.com
    radioactivita.com pandemic.radioactivita.com modernart.radioactivita.com].freeze

  def self.entries
    new.entries
  end

  def initialize(state: STATE, bootstrap: CONFIG.join("registry-bootstrap.json"), key: CONFIG.join("publisher.pem"))
    @state, @bootstrap, @key = state, bootstrap, key
  end

  def entries
    verified(local_bundle, fresh: false).last
  rescue Invalid, JSON::ParserError, KeyError, ArgumentError, SystemCallError, OpenSSL::OpenSSLError
    []
  end

  def refresh
    bundle = {}
    %w[current.json current.json.sig].each { |name| bundle[name] = fetch(name) }
    pointer = verify_pointer(bundle, fresh: true)
    prefix = "versions/#{pointer.fetch('version')}/"
    previous = local_bundle
    names = ([ "manifest.json" ] + PAYLOADS).map { |name| prefix + name }
    if previous[prefix + "manifest.json"].present? &&
        Digest::SHA256.hexdigest(previous.fetch(prefix + "manifest.json")) == pointer.fetch("manifest_sha256")
      bundle.merge!(previous.slice(*names))
    else
      names.each { |name| bundle[name] = fetch(name) }
    end

    File.open("#{@state}.lock", File::WRONLY | File::CREAT, 0o600) do |lock|
      lock.flock(File::LOCK_EX)
      sequence, = verified(bundle, fresh: true)
      previous = local_bundle
      previous_sequence, = verified(previous, fresh: false)
      return if sequence == previous_sequence && bundle == previous
      old_pointer = parse(previous.fetch("current.json"))
      same_version_changed = old_pointer["version"] == pointer["version"] && old_pointer["manifest_sha256"] != pointer["manifest_sha256"]
      raise Invalid if sequence <= previous_sequence || same_version_changed

      Tempfile.create(".shell-registry", @state.dirname) do |file|
        file.write(JSON.generate(bundle.transform_values { |data| Base64.strict_encode64(data) }))
        file.flush
        file.fsync
        File.rename(file.path, @state)
      end
    end
  end

  private

  def parse(json)
    value = JSON.parse(json, object_class: UniqueObject)
    raise Invalid unless value.is_a?(Hash)

    value
  end

  def local_bundle
    path = @state.exist? ? @state : @bootstrap
    parse(path.binread(MAX_BYTES * 16)).transform_values do |data|
      raise Invalid unless data.is_a?(String)

      Base64.strict_decode64(data)
    end
  end

  def fetch(name)
    response = HTTP.timeout(4).headers("Cache-Control" => "no-cache, no-store").get(ORIGIN + name)
    raise Invalid unless response.status == 200

    data = +"".b
    response.body.each do |chunk|
      data << chunk
      raise Invalid if data.bytesize > MAX_BYTES
    end
    data
  end

  def verify_pointer(bundle, fresh:)
    message = bundle.fetch("current.json")
    signature = bundle.fetch("current.json.sig")
    raise Invalid unless signature.bytesize == 64 && OpenSSL::PKey.read(File.binread(@key)).verify(nil, signature, message)

    pointer = parse(message)
    version, digest, sequence, issued, expires = pointer.values_at("version", "manifest_sha256", "sequence", "issued_at", "expires_at")
    now = Time.current.to_i
    unless version.is_a?(String) && VERSION.match?(version) && digest.is_a?(String) && /\A[0-9a-f]{64}\z/.match?(digest) &&
        sequence.is_a?(Integer) && sequence.positive? && issued.is_a?(Integer) && expires.is_a?(Integer) &&
        issued <= now && (1..86_400).cover?(expires - issued) && (!fresh || now < expires)
      raise Invalid
    end
    pointer
  end

  def verified(bundle, fresh:)
    pointer = verify_pointer(bundle, fresh:)
    version = pointer.fetch("version")
    prefix = "versions/#{version}/"
    manifest_raw = bundle.fetch(prefix + "manifest.json")
    raise Invalid unless Digest::SHA256.hexdigest(manifest_raw) == pointer.fetch("manifest_sha256")

    manifest = parse(manifest_raw)
    hashes = manifest.fetch("files")
    unless manifest.values_at("version", "behavior_baseline", "registry_schema") == [ version, "shell-v1", 1 ] &&
        hashes.is_a?(Hash) && hashes.keys.sort == PAYLOADS.sort &&
        hashes.all? { |name, hash| Digest::SHA256.hexdigest(bundle.fetch(prefix + name)) == hash }
      raise Invalid
    end

    registry = parse(bundle.fetch(prefix + "application-shell-registry.json"))
    entries = registry.fetch("applications")
    unless registry.values_at("schema_version", "specification_version") == [ 1, version ] &&
        entries.is_a?(Array) && entries.size <= 64 && entries.all? { |entry| valid_entry?(entry) } &&
        entries.pluck("id").uniq.size == entries.size && entries.pluck("canonical_url").uniq.size == entries.size
      raise Invalid
    end
    [ pointer.fetch("sequence"), entries ]
  end

  def valid_entry?(entry)
    return false unless entry.is_a?(Hash) && entry.keys.sort == %w[availability canonical_url id name]

    id, name, url, availability = entry.values_at("id", "name", "canonical_url", "availability")
    return false unless [ id, name, url ].all? { |value| value.is_a?(String) } && ID.match?(id) &&
      name.present? && %w[production withdrawn].include?(availability) &&
      %r{\Ahttps://(?:[a-z0-9]+(?:-[a-z0-9]+)*\.)+[a-z]{2,}/\z}.match?(url)

    host = URI(url).host
    !%w[auth infrastructure site-art].include?(id) && !EXCLUDED_HOSTS.include?(host) && !host.match?(/staging|preview/)
  end
end
