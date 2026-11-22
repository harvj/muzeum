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
    expect(discovery.call(surface, [ candidate ], checked: nil, attempted: stale_claim, search: false).pluck("id")).to eq([ candidate["id"] ])
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
    discovery.call(surface, [ candidate ], checked: nil, attempted: stale_claim, search: false)
    expect(discovery.tracklists.fetch(release_id)).to include("state" => "unavailable", "http_status" => 503)
    expect(client).to receive(:edition).with(session, release_id, catalog: true).and_return(edition)
    discovery.call(surface, [], checked: nil, attempted: stale_claim, search: false, preferred: release_id)
    expect(discovery.tracklists.fetch(release_id)).to include("state" => "complete")
  end

  it "keeps the same independently supported ranking with missing, stale, and misleading source IDs" do
    supported = candidate.merge("title" => "Influence")
    incompatible = candidate.merge("id" => SecureRandom.uuid, "title" => "Different track")
    evidence = { "candidates" => [ incompatible, supported ],
      "review_tracklists" => { release_id => RecordingResolution::ReviewRelease.project(edition) } }
    [ {}, claims, { "track_mbid" => incompatible["id"], "artist_mbid" => SecureRandom.uuid, "album_mbid" => release_id } ].each do |hints|
      ranks = RecordingResolution::Ranking.call(surface, evidence.merge("source_claims" => hints,
        "verified_recording" => incompatible), source_hints: true)
      expect(ranks.pluck("recording_mbid")).to eq([ supported["id"] ])
      expect(ranks.first.dig("inputs", "recording_identifier", "weight")).to eq(0)
      expect(ranks.first.dig("source", "claims")).to eq(hints)
    end
  end

  it "retains identical independent tracklist evidence and ranks across real Lady Wood claim variants" do
    # Search may supply only a release identifier. The detailed response supplies the actual edition title.
    row = candidate.merge("releases" => [ { "id" => release_id } ])
    hints = [
      {},
      { "album_mbid" => release_id, "track_mbid" => candidate["id"], "artist_mbid" => candidate.dig("artist-credit", 0, "artist", "id") },
      { "album_mbid" => stale_claim, "track_mbid" => SecureRandom.uuid },
      { "album_mbid" => SecureRandom.uuid, "artist_mbid" => SecureRandom.uuid }
    ]
    artist_id = candidate.dig("artist-credit", 0, "artist", "id")
    Artist.create!(mbid: artist_id, name: "Tove Lo")
    catalog_identity = RecordingResolution::LocalCandidates.catalog_identity(surface)
    expect(catalog_identity).to eq(artist_mbid: artist_id)
    results = hints.map do |source_claims|
      paths = []
      replay = double(provenance: session.provenance)
      allow(replay).to receive(:get) do |_provider, path, params:, &project|
        paths << path
        expect(params.fetch(:query)).to include("arid:#{artist_id}") if %w[/ws/2/recording /ws/2/release].include?(path)
        response = case path
        when "/ws/2/recording" then { "recordings" => [ row ], "count" => 1, "offset" => params.fetch(:offset) }
        when "/ws/2/release" then { "releases" => [] }
        when "/ws/2/release/#{release_id}" then edition
        else raise "Unexpected provider lookup #{path}"
        end
        { "data" => project.call(response) }
      end
      evidence = RecordingResolution::Evaluator.new(replay, discogs: nil, workspace: true, catalog_identity:).call(surface, source_claims)
      expect(evidence["source_claims"]).to eq(source_claims)
      ranks = RecordingResolution::Ranking.call(surface, evidence, source_hints: true).map do |rank|
        rank.merge("source" => rank.fetch("source").except("claims"))
      end
      [ evidence.slice("candidates", "discovery_appearances", "review_tracklists", "edition", "slots"), ranks, paths ]
    end
    expect(results.uniq.size).to eq(1)
    evidence, ranking, paths = results.first
    expect(evidence.dig("discovery_appearances", candidate["id"])).to include(include("id" => release_id, "position" => be_positive))
    expect(ranking.first.dig("inputs", "catalog_release_appearance", "provenance", "id")).to eq(release_id)
    expect(paths).to eq([ "/ws/2/recording", "/ws/2/release", "/ws/2/release/#{release_id}" ])
  end

  it "looks up the stored release edition when its local tracklist cannot be reused" do
    artist_id = candidate.dig("artist-credit", 0, "artist", "id")
    artist = Artist.create!(mbid: artist_id, name: "Tove Lo")
    release = Release.create!(title: "Lady Wood", ingested_from_release_mbid: release_id, catalog_verified_at: Time.current)
    release.release_artists.create!(artist:)
    identity = RecordingResolution::LocalCandidates.catalog_identity(surface)
    expect(identity).to eq(artist_mbid: artist_id, edition_mbid: release_id)
    expect(session).to receive(:get).with(:musicbrainz, "/ws/2/recording", params: hash_including(query: include("arid:#{artist_id}"))).ordered do |*_, &project|
      { "data" => project.call("recordings" => [ candidate ], "count" => 1, "offset" => 0) }
    end
    expect(session).to receive(:get).with(:musicbrainz, "/ws/2/release/#{release_id}", params: anything).ordered do |*_, &project|
      { "data" => project.call(edition) }
    end
    evidence = RecordingResolution::Evaluator.new(session, discogs: nil, workspace: true, catalog_identity: identity).call(surface, claims)
    expect(evidence.dig("edition", "id")).to eq(release_id)
    expect(evidence.dig("discovery_appearances", candidate.fetch("id"))).to be_present
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
