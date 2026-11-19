require "rails_helper"

RSpec.describe SiteArt do
  subject(:cache) { described_class.new }

  let(:endpoint) { described_class::MANIFEST.to_s }
  let(:digest) { "a" * 64 }
  let(:url) { "https://art.harvj.com/assets/#{digest}.jpg" }
  let(:record) do
    { "url" => url, "sha256" => digest, "media_type" => "image/jpeg", "bytes" => 10, "rights" => "Original" }
  end
  let(:manifest) do
    { "schema_version" => 1, "commit" => "b" * 40, "release" => "c" * 64,
      "assets" => { "muzeum.background_light" => record } }
  end
  let(:time) { [ 0 ] }

  before { allow(cache).to receive(:monotonic_time) { time.first } }

  def finish_refresh
    thread = cache.instance_variable_get(:@refreshing)
    expect(thread.join(2)).to eq(thread) if thread
  end

  it "serves immediately, coalesces refreshes, revalidates with ETag, and adopts a new publication" do
    entered = Queue.new
    release = Queue.new
    first = stub_request(:get, endpoint).to_return do
      entered << true
      release.pop
      { body: manifest.to_json, headers: { "ETag" => '"v1"' } }
    end

    expect(cache.snapshot).to eq({})
    Timeout.timeout(2) { entered.pop }
    expect(Array.new(12) { Thread.new { cache.snapshot } }.map(&:value)).to all(eq({}))
    release << true
    finish_refresh
    expect(cache.snapshot).to eq(light: url)
    expect(first).to have_been_requested.once

    conditional = stub_request(:get, endpoint).with(headers: { "If-None-Match" => '"v1"' }).to_return(status: 304)
    time[0] += 60
    expect(cache.snapshot).to eq(light: url)
    finish_refresh
    expect(conditional).to have_been_requested.once
    expect(cache.snapshot).to eq(light: url)

    # Removing an ID from a valid manifest restores that slot's local artwork.
    manifest["assets"] = { "muzeum.background_dark" => record }
    conditional.to_return(body: manifest.to_json)
    time[0] += 60
    cache.snapshot
    finish_refresh
    expect(cache.snapshot).to eq(dark: url)
  end

  it "retains the last good snapshot through malformed, oversized, or untrusted manifests and transport failures" do
    stub_request(:get, endpoint).to_return(body: manifest.to_json)
    cache.snapshot
    finish_refresh
    expect(cache.snapshot).to eq(light: url)

    invalid_documents = [
      "{",
      " " * (described_class::MAX_MANIFEST_BYTES + 1),
      manifest.to_json.sub('"schema_version":1', '"schema_version":1,"schema_version":1'),
      manifest.merge("schema_version" => 2).to_json,
      manifest.to_json.sub("https://art.harvj.com/", "https://art.harvj.com.evil.example/"),
      manifest.to_json.sub(".jpg", ".jpg?mutable=true"),
      manifest.to_json.sub(".jpg", ".svg"),
      manifest.to_json.sub("/#{digest}", "/#{'d' * 64}")
    ]
    invalid_documents.each do |body|
      stub_request(:get, endpoint).to_return(body: body)
      time[0] += 60
      expect(cache.snapshot).to eq(light: url)
      finish_refresh
      expect(cache.snapshot).to eq(light: url)
    end

    stub_request(:get, endpoint).to_raise(SocketError).then.to_timeout.then.to_return(status: 503)
    3.times do
      time[0] += 60
      cache.snapshot
      finish_refresh
      expect(cache.snapshot).to eq(light: url)
    end
  end

  it "bounds a slow response without delaying the caller" do
    stub_request(:get, endpoint).to_return do
      sleep 3
      { body: manifest.to_json }
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect(cache.snapshot).to eq({})
    finish_refresh
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 2
    expect(cache.snapshot).to eq({})
  end
end
