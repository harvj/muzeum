require "rails_helper"

RSpec.describe ApplicationShellEvidence do
  let(:at) { 1_795_219_200 }
  let(:grant) { "test-only-refresh-grant" }
  let(:evidence) do
    { "iss" => OidcClient::ISSUER, "aud" => "muzeum-test", "sub" => "verified-subject", "version" => "1",
      "grant_binding" => Digest::SHA256.hexdigest(grant), "preferred_username" => "alex",
      "eligible_destination_ids" => %w[continuum remote-gaming], "iat" => at, "exp" => at + 60 }
  end

  def validate(value, now: at)
    described_class.validate({ "active" => true, "application_shell" => value },
      subject: "verified-subject", client_id: "muzeum-test", grant:, now:)
  end

  it "accepts current Auth evidence, including a verified username with zero eligible applications" do
    expect(validate(evidence)).to eq(username: "alex", destinations: %w[continuum remote-gaming], expires_at: at + 60)
    expect(validate(evidence.merge("eligible_destination_ids" => []))).to include(destinations: [])
  end

  it "rejects stale, foreign, malformed or excessively long-lived evidence" do
    { "aud" => "other-client", "iss" => "https://elsewhere.example", "sub" => "other-subject",
      "grant_binding" => "0" * 64, "exp" => at + 61, "iat" => at + 1,
      "preferred_username" => "other@example.test", "eligible_destination_ids" => [ "continuum", "continuum" ],
      "version" => "2" }.each do |field, value|
      expect(validate(evidence.merge(field => value))).to be_nil
    end
    expect(validate(evidence, now: at + 60)).to be_nil
  end
end

RSpec.describe ApplicationShellRegistry do
  def entry(id, name, host, availability = "production")
    { id:, name:, canonical_url: "https://#{host}/", availability: }
  end

  let(:entries) do
    [ entry("muzeum", "Muzeum", "muzeum.fm"), entry("remote-gaming", "Remote-Gaming", "gaming.harvj.com"),
      entry("continuum", "Library", "library.harvj.com"), entry("continuum-engine", "Continuum Engine", "funding.harvj.com", "withdrawn") ]
  end

  def replace(path, entries, sequence: 1, version: "1.1.0")
    registry = { schema_version: 1, specification_version: version, applications: entries }
    raw = registry.to_json
    value = { format_version: 1, specification_version: version, sequence:,
      manifest_sha256: "a" * 64, pointer_sha256: "b" * 64, registry_sha256: Digest::SHA256.hexdigest(raw),
      registry_json: raw, registry: }
    File.write("#{path}.next", value.to_json)
    File.rename("#{path}.next", path)
  end

  it "uses local publication order and updates a running reader after an atomic replacement" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "registry.json")
      replace(path, entries)
      allowed = %w[muzeum remote-gaming continuum continuum-engine first second]
      expect(described_class.destinations(allowed, path:).pluck(:name)).to eq([ "Remote-Gaming", "Library" ])
      expect(described_class.destinations([], path:)).to be_empty
      expect(described_class.destinations(%w[continuum], path:)).to eq([ { name: "Library", url: "https://library.harvj.com/" } ])
      inserted = [ entry("first", "First", "first.example"), entry("second", "Second", "second.example") ]
      replace(path, entries.dup.insert(2, *inserted), sequence: 2, version: "1.1.1")
      expect(described_class.destinations(allowed, path:).pluck(:name)).to eq([ "Remote-Gaming", "First", "Second", "Library" ])
      expect(described_class.destinations(allowed, path: "#{directory}/missing")).to be_empty
      link = "#{directory}/symlink.json"
      File.symlink(path, link)
      expect(described_class.destinations(allowed, path: link)).to be_empty
      File.chmod(0o664, path)
      expect(described_class.destinations(allowed, path:)).to be_empty
    end
  end

  it "rejects malformed, duplicate and excluded destinations as a unit" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "registry.json")
      [ entries.first, entry("auth", "Auth", "auth.harvj.com"), entry("fake", "Fake", "preview.example") ].each do |bad|
        replace(path, entries + [ bad ])
        expect(described_class.destinations(%w[continuum], path:)).to be_empty
      end
    end
  end
end
