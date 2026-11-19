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
    expect(cache.snapshot).to eq(release: manifest.fetch("release"), light: { "url" => url })
    expect(first).to have_been_requested.once

    conditional = stub_request(:get, endpoint).with(headers: { "If-None-Match" => '"v1"' }).to_return(status: 304)
    time[0] += 60
    expect(cache.snapshot).to eq(release: manifest.fetch("release"), light: { "url" => url })
    finish_refresh
    expect(conditional).to have_been_requested.once
    expect(cache.snapshot).to eq(release: manifest.fetch("release"), light: { "url" => url })

    # Removing an ID from a valid manifest restores that slot's local artwork.
    manifest["assets"] = { "muzeum.background_dark" => record }
    conditional.to_return(body: manifest.to_json)
    time[0] += 60
    cache.snapshot
    finish_refresh
    expect(cache.snapshot).to eq(release: manifest.fetch("release"), dark: { "url" => url })
  end

  it "retains the last good snapshot through malformed, oversized, or untrusted manifests and transport failures" do
    stub_request(:get, endpoint).to_return(body: manifest.to_json)
    cache.snapshot
    finish_refresh
    expect(cache.snapshot).to eq(release: manifest.fetch("release"), light: { "url" => url })

    invalid_documents = [
      "{",
      " " * (described_class::MAX_MANIFEST_BYTES + 1),
      manifest.to_json.sub('"schema_version":1', '"schema_version":1,"schema_version":1'),
      manifest.merge("schema_version" => 2).to_json,
      manifest.to_json.sub("https://art.harvj.com/", "https://art.harvj.com.evil.example/"),
      manifest.to_json.sub(".jpg", ".jpg?mutable=true"),
      manifest.to_json.sub(".jpg", ".svg"),
      manifest.to_json.sub(".jpg", ".html").sub('"image/jpeg"', 'false'),
      manifest.to_json.sub("/#{digest}", "/#{'d' * 64}")
    ]
    invalid_documents.each do |body|
      stub_request(:get, endpoint).to_return(body: body)
      time[0] += 60
      expect(cache.snapshot).to eq(release: manifest.fetch("release"), light: { "url" => url })
      finish_refresh
      expect(cache.snapshot).to eq(release: manifest.fetch("release"), light: { "url" => url })
    end

    stub_request(:get, endpoint).to_raise(SocketError).then.to_timeout.then.to_return(status: 503)
    3.times do
      time[0] += 60
      cache.snapshot
      finish_refresh
      expect(cache.snapshot).to eq(release: manifest.fetch("release"), light: { "url" => url })
    end
  end

  let(:presentation) do
    { "foreground" => "#f5EFE3",
      "text_shadow" => { "color" => "#161412", "opacity_percent" => 40, "blur_px" => 2, "x_px" => -4, "y_px" => 1 },
      "backing" => { "color" => "#161412", "opacity_percent" => 14 } }
  end

  it "accepts either presentation field, both or neither, and refreshes treatment at the same URL" do
    original = record.merge("foreground" => "light")
    manifest["assets"]["muzeum.background_light"] = original
    request = stub_request(:get, endpoint).to_return(body: manifest.to_json)
    cache.snapshot
    finish_refresh
    expect(cache.snapshot.fetch(:light)).to eq("url" => url, "foreground" => "light")

    [ original.merge("presentation" => presentation), record.merge("presentation" => presentation), record ].each do |update|
      manifest["release"] = SecureRandom.hex(32)
      manifest["assets"]["muzeum.background_light"] = update
      request.to_return(body: manifest.to_json)
      time[0] += 60
      cache.snapshot
      finish_refresh
      expect(cache.snapshot).to eq(release: manifest.fetch("release"), light: update.slice("url", "foreground", "presentation"))
      expect(cache.snapshot.dig(:light, "presentation", "backing")).to be_frozen
    end
  end

  it "keeps supported partial regional treatments and discards unknown presentation extensions" do
    record["presentation"] = presentation.merge(
      "gradient" => { "color" => "ignored" },
      "regions" => { "top" => { "foreground" => "#123456", "effect" => "ignored" },
        "bottom" => { "backing" => { "color" => "#654321", "opacity_percent" => 20 } },
        "side" => { "foreground" => "ignored" } })
    stub_request(:get, endpoint).to_return(body: manifest.to_json)
    cache.snapshot
    finish_refresh
    expect(cache.snapshot.dig(:light, "presentation")).to eq(presentation.merge(
      "regions" => { "top" => { "foreground" => "#123456" },
        "bottom" => { "backing" => { "color" => "#654321", "opacity_percent" => 20 } } }))
  end

  it "validates metadata on unconsumed records and retains the last known good snapshot" do
    request = stub_request(:get, endpoint).to_return(body: manifest.to_json)
    cache.snapshot
    finish_refresh
    original = cache.snapshot
    invalid = [
      nil, [], {}, { "foreground" => "#123456\n" }, { "foreground" => "white; color: red" },
      { "regions" => [] }, { "regions" => {} }, { "regions" => { "top" => {} } },
      { "regions" => { "bottom" => { "foreground" => "red" } } },
      { "backing" => { "color" => "#123456", "opacity_percent" => 51 } },
      { "backing" => { "color" => "#123456", "opacity_percent" => 20.0 } },
      { "backing" => { "color" => "#12345678", "opacity_percent" => 20 } },
      { "text_shadow" => presentation.fetch("text_shadow").merge("blur_px" => 9) },
      { "text_shadow" => presentation.fetch("text_shadow").merge("x_px" => -5) },
      { "text_shadow" => presentation.fetch("text_shadow").merge("y_px" => 5) },
      { "text_shadow" => presentation.fetch("text_shadow").merge("opacity_percent" => 61) },
      { "text_shadow" => presentation.fetch("text_shadow").except("y_px") }
    ]
    invalid.each do |value|
      manifest["assets"]["other.background"] = record.merge("presentation" => value)
      request.to_return(body: manifest.to_json)
      time[0] += 60
      cache.snapshot
      finish_refresh
      expect(cache.snapshot).to be(original), "accepted malformed presentation #{value.inspect}"
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
