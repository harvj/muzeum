require "rails_helper"

RSpec.describe RecordingResolution::EditionDiscovery do
  let(:edition) { JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/releases/lady_wood_vinyl.json").read) }
  let(:release_id) { edition.fetch("id") }
  let(:stale_claim) { "0a85f0ea-e752-40e8-a609-d2196f29cef5" }
  let(:surface) { RecordingResolution::RealCorpusEvaluation::Observation.new(artist: "Tove Lo", album: "Lady Wood", track: "Influence") }
  let(:claims) { { "album_mbid" => stale_claim } }
  let(:candidate) do
    track = edition.fetch("media").first.fetch("tracks").find { |row| row["title"] == "Influence" }
    track.fetch("recording").merge("releases" => [ edition.slice("id", "title") ])
  end
  let(:session) do
    instance_double(RecordingResolution::ProviderSession, provenance: [
      { "endpoint" => "/ws/2/release/#{stale_claim}", "retrieved_at" => "2026-11-21T20:00:00Z" },
      { "endpoint" => "/ws/2/release/#{release_id}", "retrieved_at" => "2026-11-21T20:00:01Z" }
    ])
  end
  let(:client) { Clients::Musicbrainz.new }

  it "checks the candidate edition after an unavailable source claim and retains the real slot and provenance" do
    expect(session).to receive(:get).with(:musicbrainz, "/ws/2/release/#{release_id}", params: anything) do |*_, &project|
      { "data" => project.call(edition) }
    end
    discovery = described_class.new(client, session)
    expect(discovery.call(surface, claims, [ candidate ], checked: nil, attempted: stale_claim, search: false)).to be_empty
    expect(discovery.tracklists.fetch(stale_claim)).to include("state" => "missing")
    tracklist = discovery.tracklists.fetch(release_id)
    expect(tracklist).to include("state" => "complete", "provider" => "musicbrainz", "retrieved_at" => "2026-11-21T20:00:01Z")
    expect(tracklist.fetch("media").first.fetch("tracks")).to include(include("recording_mbid" => candidate["id"], "length" => be_positive))
    rank = RecordingResolution::Ranking.call(surface, { "candidates" => [ candidate ], "review_tracklists" => discovery.tracklists }).first
    expect(rank.dig("inputs", "catalog_release_appearance", "state")).to eq("positive")
  end

  it "retains a retryable failure and fetches that exact release on retry" do
    discovery = described_class.new(client, session)
    allow(client).to receive(:edition).with(session, release_id, catalog: true)
      .and_raise(RecordingResolution::ProviderError.new("provider unavailable", http_status: 503))
    discovery.call(surface, claims, [ candidate ], checked: nil, attempted: stale_claim, search: false)
    expect(discovery.tracklists.fetch(release_id)).to include("state" => "unavailable", "http_status" => 503)
    expect(client).to receive(:edition).with(session, release_id, catalog: true).and_return(edition)
    discovery.call(surface, claims, [], checked: nil, attempted: stale_claim, search: false, preferred: release_id)
    expect(discovery.tracklists.fetch(release_id)).to include("state" => "complete")
  end

  it "keeps disc grouping and leaves unknown durations empty" do
    corpus = JSON.parse(Rails.root.join("spec/fixtures/recording_resolution/discovery/corpus.json").read)
    concert = corpus.fetch("releases").fetch("1586bf99-c5dd-4b0b-9c1e-a94cf3925e52")
    track = concert.fetch("media").last.fetch("tracks").first
    track.delete("length")
    track.fetch("recording").delete("length")
    media = RecordingResolution::ReviewRelease.project(concert).fetch("media")
    expect(media.pluck("position")).to eq([ 1, 2 ])
    expect(media.last.fetch("tracks").first["length"]).to be_nil
  end
end
