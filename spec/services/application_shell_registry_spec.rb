require "rails_helper"
require "tmpdir"

RSpec.describe ApplicationShellRegistry do
  include ActiveSupport::Testing::TimeHelpers

  it "uses the pinned signed bootstrap with no request to the publisher" do
    expect(described_class.entries.pluck("id")).to eq(%w[muzeum remote-gaming continuum continuum-engine])
  end

  it "retains a renewed, verified snapshot across outages and rejects replay and tampering" do
    Dir.mktmpdir do |dir|
      key = OpenSSL::PKey.generate_key("ED25519")
      root = Pathname(dir)
      state = root.join("cache.json")
      bootstrap = root.join("bootstrap.json")
      public_key = root.join("publisher.pem")
      public_key.write(key.public_to_pem)
      original = JSON.parse(described_class::CONFIG.join("registry-bootstrap.json").read).transform_values { |value| Base64.strict_decode64(value) }
      now = Time.current.to_i
      pointer = JSON.parse(original.fetch("current.json")).merge("sequence" => 10, "issued_at" => now - 400, "expires_at" => now - 1)
      encode_pointer = lambda do |value|
        raw = JSON.generate(value)
        { "current.json" => raw, "current.json.sig" => key.sign(nil, raw) }
      end
      bootstrap.write(JSON.generate(original.merge(encode_pointer.call(pointer)).transform_values { |value| Base64.strict_encode64(value) }))
      registry = described_class.new(state: state, bootstrap: bootstrap, key: public_key)
      expect(registry.entries.pluck("id")).to include("muzeum")
      updated = encode_pointer.call(pointer.merge("sequence" => 11, "issued_at" => now - 1, "expires_at" => now + 60))
      updated.each do |path, value|
        stub_request(:get, described_class::ORIGIN + path).to_return(body: value)
      end
      registry.refresh
      saved = state.read
      expect(described_class.new(state: state, bootstrap: bootstrap, key: public_key).entries).to eq(registry.entries)
      travel 2.minutes do
        expect { registry.refresh }.to raise_error(described_class::Invalid)
        expect(registry.entries.pluck("id")).to include("muzeum")
      end
      replay = encode_pointer.call(pointer.merge("sequence" => 9, "issued_at" => now - 1, "expires_at" => now + 60))
      replay.each { |path, value| stub_request(:get, described_class::ORIGIN + path).to_return(body: value) }
      expect { registry.refresh }.to raise_error(described_class::Invalid)
      expect(state.read).to eq(saved)
      registry_path = "versions/1.1.0/application-shell-registry.json"
      manifest_path = "versions/1.1.0/manifest.json"
      replacement = JSON.parse(original.fetch(registry_path))
      replacement.fetch("applications").find { |item| item.fetch("id") == "remote-gaming" }["availability"] = "withdrawn"
      replacement["specification_version"] = "1.1.1"
      replacement = JSON.generate(replacement)
      manifest = JSON.parse(original.fetch(manifest_path))
      manifest["version"] = "1.1.1"
      manifest.fetch("files")["application-shell-registry.json"] = Digest::SHA256.hexdigest(replacement)
      manifest = JSON.generate(manifest)
      next_bundle = original.merge(registry_path => replacement, manifest_path => manifest)
        .transform_keys { |path| path.sub("versions/1.1.0/", "versions/1.1.1/") }.merge(
        encode_pointer.call(pointer.merge("sequence" => 12, "issued_at" => now - 1, "expires_at" => now + 60,
          "version" => "1.1.1", "manifest_sha256" => Digest::SHA256.hexdigest(manifest)))
      )
      next_bundle.each { |path, value| stub_request(:get, described_class::ORIGIN + path).to_return(body: value) }
      registry.refresh
      expect(registry.entries.find { |item| item.fetch("id") == "remote-gaming" }.fetch("availability")).to eq("withdrawn")
      [ "{}", "[]", '{"current.json":null}' ].each do |corrupt|
        state.write(corrupt)
        expect(registry.entries).to be_empty
      end
    end
  end
end
