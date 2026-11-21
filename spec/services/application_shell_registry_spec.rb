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
      state.write("{}")
      expect(registry.entries).to be_empty
    end
  end
end
