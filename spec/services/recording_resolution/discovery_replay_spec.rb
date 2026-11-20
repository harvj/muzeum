require "rails_helper"
require Rails.root.join("spec/support/discovery_replay")

RSpec.describe RecordingResolution::EditionDiscovery do
  let(:fixture) { JSON.parse(Rails.root.join("spec/fixtures/recording_resolution/discovery/corpus.json").read) }
  let(:examples) { fixture.fetch("cases").index_by { |example| example.fetch("id") } }

  it "recovers all seven reviewed identities within the replay request budget" do
    examples.each_value do |example|
      baseline = DiscoveryReplay.run(fixture, example, discover: false)
      discovered = DiscoveryReplay.run(fixture, example, discover: true)

      expect(baseline.fetch("surfaced")).to be(false), example.fetch("id")
      expect(discovered.fetch("surfaced")).to be(true), example.fetch("id")
      expect(discovered.fetch("calls")).to be <= 5
      expect(discovered.fetch("paths").grep(%r{\A/ws/2/release/}).tally.values).to all(eq(1))
      expect(discovered.fetch("ranking").pluck("recording_mbid")).to eq(discovered.fetch("ranking").pluck("recording_mbid").uniq)
    end
  end

  it "gives checked Regent's Court appearances equal weight while preserving distinct alternatives" do
    result = DiscoveryReplay.run(fixture, examples.fetch("regents-court-292999"), discover: true)

    expect(result.fetch("ranking").pluck("recording_mbid")).to eq(%w[
      0772fc8e-567b-47ed-bbcc-15d9c2fa46b6
      1a5b8b34-3f99-454d-96d2-82f200cfffe2
      914eb7fc-0faf-4067-87b1-9f74db1d4f99
    ])
    expect(result.fetch("ranking").pluck("score")).to eq([ 8, 8, 7 ])
    expect(result.fetch("recommendation")).to eq("withheld")
  end

  it "retains the three real Regent's Court tracklists during explicit review with one additional lookup" do
    daytrotter = JSON.parse(Rails.root.join("spec/fixtures/recording_resolution/discovery/daytrotter.json").read)
    fixture.fetch("releases")[daytrotter.fetch("id")] = daytrotter

    result = DiscoveryReplay.run(fixture, examples.fetch("regents-court-292999"), discover: true, review_alternative: true)
    lists = result.fetch("tracklists")
    expect(result.fetch("calls")).to eq(6)
    expect(lists.values.pluck("state")).to all(eq("complete"))
    expect(lists.values.map { |list| list.fetch("media").first.fetch("tracks").size }).to eq([ 18, 14, 4 ])
    expect(lists.fetch(daytrotter.fetch("id")).fetch("media").first.fetch("tracks").second)
      .to include("number" => "2", "length" => 123000, "recording_mbid" => "914eb7fc-0faf-4067-87b1-9f74db1d4f99")
    expect(result.fetch("ranking").pluck("score")).to eq([ 8, 8, 7 ])
  end

  it "distinguishes missing provider track data from a retained incomplete medium" do
    edition = fixture.fetch("releases").fetch("96fdedfd-ba26-4ff4-a7bc-faf54879f158")
    missing = RecordingResolution::ReviewRelease.project(edition.except("media"))
    expect(missing).to include("state" => "missing", "media" => [])

    edition.fetch("media").first.fetch("tracks").pop
    partial = RecordingResolution::ReviewRelease.project(edition)
    expect(partial.fetch("state")).to eq("incomplete")
    expect(partial.fetch("media").first.fetch("tracks").size).to eq(17)
  end

  it "withholds a badge when a verified studio identifier conflicts with a checked live appearance" do
    example = examples.fetch("wembley-misleading-studio-only")
    expect(DiscoveryReplay.run(fixture, example, discover: false).fetch("recommendation")).to eq("false_positive")
    expect(DiscoveryReplay.run(fixture, example, discover: true).fetch("recommendation")).to eq("withheld")
  end

  it "cannot recover a deluxe-only bonus track from an incomplete medium" do
    fixture.fetch("releases").fetch("96fdedfd-ba26-4ff4-a7bc-faf54879f158").fetch("media").first.fetch("tracks").shift

    result = DiscoveryReplay.run(fixture, examples.fetch("new-bonus-track"), discover: true)

    expect(result.fetch("surfaced")).to be(false)
  end

  it "cannot add a recording with a contradictory canonical artist identifier" do
    example = examples.fetch("new-bonus-track")
    (example["claims"] ||= {})["artist_mbid"] = "dc6b33ac-c649-414d-bd5d-b6403d23969c"

    expect(DiscoveryReplay.run(fixture, example, discover: true).fetch("surfaced")).to be(false)
  end

  it "finds the typographic title variant in a large local recording catalog" do
    Recording.connection.execute(<<~SQL)
      INSERT INTO recordings (title, mbid, created_at, updated_at)
      SELECT 'Unrelated recording ' || n, md5('discovery-test:' || n)::uuid, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM generate_series(1, 20000) n
    SQL
    recording = Recording.create!(title: "Regent’s Court", mbid: SecureRandom.uuid)
    surface = RecordingResolution::RealCorpusEvaluation::Observation.new(
      artist: "The Get Up Kids", album: "There Are Rules (Deluxe Edition)", track: "Regent's Court")

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect(RecordingResolution::LocalCandidates.call(surface, {}).pluck("id")).to eq([ recording.mbid ])
    elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1_000
    warn format("Local discovery, 20k distractors: %.2f ms", elapsed) if ENV["MEASURE_DISCOVERY"]
  end
end
