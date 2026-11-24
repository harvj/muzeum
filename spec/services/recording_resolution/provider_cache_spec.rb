require "rails_helper"
require_relative "../../support/narrow_stairs_fixture"

RSpec.describe RecordingResolution::ProviderSession do
  include ActiveSupport::Testing::TimeHelpers
  include NarrowStairsFixture

  let(:token) { SecureRandom.uuid }
  let(:work) do
    CatalogImport.create!(kind: "recording_investigation", entity_id: 1, state: "refreshing", due_at: Time.current,
      lease_token: token, lease_until: 2.minutes.from_now)
  end
  let(:session) { described_class.new(work, token, catalog: true) }
  let(:client) { Clients::Musicbrainz.new }
  let(:base_url) { "https://musicbrainz.org/ws/2" }
  let(:group_query) { { fmt: "json", "release-group" => NarrowStairsFixture::GROUP, limit: 25 } }

  def stub_json(path, query, body)
    stub_request(:get, "#{base_url}#{path}").with(query:).to_return do
      travel 1.second
      { status: 200, body: body.to_json }
    end
  end

  it "sends the refresh 57 release-group request and assembles the verified Narrow Stairs original" do
    id = NarrowStairsFixture::RECORDING
    editions = narrow_stairs_editions
    original = editions.find { |edition| edition["id"] == NarrowStairsFixture::ORIGINAL }
    recording = original.dig("media", 0, "tracks", 2, "recording")
    appearances = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/construction/narrow_stairs_recordings.json").read).fetch(id)
      .select { |edition| edition.dig("release-group", "id") == NarrowStairsFixture::GROUP }
    stub_json("/recording/#{id}", { fmt: "json", inc: "artist-credits+releases+release-groups+isrcs+genres+tags+recording-rels" }, recording)
    stub_json("/release", { fmt: "json", recording: id, inc: "release-groups+media", limit: 25 },
      { "release-count" => appearances.size, "release-offset" => 0, "releases" => appearances })
    group_request = stub_json("/release", group_query, { "release-count" => editions.size, "release-offset" => 0, "releases" => editions })
    edition_requests = editions.to_h do |edition|
      [ edition.fetch("id"), stub_json("/release/#{edition.fetch("id")}",
        { fmt: "json", inc: "recordings+artist-credits+release-groups+url-rels+release-rels+genres+tags+isrcs" }, edition) ]
    end

    freeze_time do
      origins = RecordingResolution::RecordingOrigins.new(client, session)
      evidence = origins.call([ id ], retained: [])
      expect(origins.call([ id ], retained: []).fetch("construction_editions")).to eq(evidence.fetch("construction_editions"))
      proposal = CanonicalCatalog::ReviewedConstruction.for(double(evidence:), id).sole
      expect(proposal.construction.base.data).to include("id" => NarrowStairsFixture::ORIGINAL, "date" => "2008-05-13", "country" => "US")
      expect(proposal.construction.base.slots.size).to eq(11)
      expect(proposal.construction.base.slots.third).to include(position: 3, title: "No Sunlight")
      expect(group_request).to have_been_requested.once
      expect(edition_requests.fetch(NarrowStairsFixture::ORIGINAL)).to have_been_requested.once
    end
  end

  it "recovers Cross You Out from separate MusicBrainz title and featured-credit fields and verifies Charli" do
    editions = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/construction/charli_featured_credit.json").read)
    album, = editions
    artist = album.fetch("artist-credit").first.dig("artist", "id")
    group = album.dig("release-group", "id")
    surface = Struct.new(:artist, :track, :album).new("Charli xcx", "Cross You Out (feat. Sky Ferreira)", "Charli")
    recording = album.dig("media", 0, "tracks", 2, "recording").merge("releases" => editions.map { |edition| edition.except("media") })
    id = recording.fetch("id")
    original_queries = [ %(arid:#{artist}), %(artist:"Charli xcx") ].map do |scope|
      %(#{scope} AND recording:"#{surface.track}")
    end
    empty = { "count" => 0, "offset" => 0, "recordings" => [] }
    params = { fmt: "json", limit: 25, offset: 0 }
    original_queries.each { |query| stub_json("/recording", params.merge(query:), empty) }
    credit_query = %(arid:#{artist} AND recording:"Cross You Out" AND artist:"Sky Ferreira")
    search = stub_json("/recording", params.merge(query: credit_query),
      { "count" => 1, "offset" => 0, "recordings" => [ recording ] })
    stub_json("/recording/#{id}", { fmt: "json", inc: "artist-credits+releases+release-groups+isrcs+genres+tags+recording-rels" }, recording)
    [ { recording: id, inc: "release-groups+media" }, { "release-group" => group } ].each do |scope|
      stub_json("/release", { fmt: "json", limit: 25 }.merge(scope),
        { "release-count" => editions.size, "release-offset" => 0, "releases" => editions })
    end
    editions.each do |edition|
      stub_json("/release/#{edition.fetch('id')}", { fmt: "json", inc: "recordings+artist-credits+release-groups+url-rels+release-rels+genres+tags+isrcs" }, edition)
    end

    freeze_time do
      evaluator = RecordingResolution::Evaluator.new(session, discogs: nil, workspace: true, origins: false,
        catalog_identity: { artist_mbid: artist, edition_mbid: album.fetch("id") })
      evidence = evaluator.call(surface, {}) do |initial|
        ranked = RecordingResolution::Ranking.call(surface, initial, source_hints: true).sole
        expect(ranked.dig("inputs", "title", "state")).to eq("positive")
        initial.merge!(RecordingResolution::RecordingOrigins.new(client, session).call([ ranked.fetch("recording_mbid") ], retained: []))
      end
      expect(evidence.fetch("recording_searches").pluck("query", "returned")).to eq([
        [ original_queries.first, 0 ], [ original_queries.last, 0 ], [ credit_query, 1 ]
      ])
      expect(evidence.fetch("candidates").sole.fetch("artist-credit").pluck("name")).to eq([ "Charli XCX", "Sky Ferreira" ])
      expect(surface.track).to eq("Cross You Out (feat. Sky Ferreira)")
      assessment = double(id: 163, evidence:)
      proposal = CanonicalCatalog::ResolutionPlan.new(assessment, id, 51).proposals.first
      base = proposal.construction.base
      expect(base.data.fetch("id")).to be_in(editions.pluck("id"))
      expect(base.slots.size).to eq(15)
      expect(base.slots.third).to include(title: "Cross You Out", source_recording_mbid: id)
      expect(search).to have_been_requested.once
    end
  end

  it "interprets explicit feature markers while preserving other parenthetical title text" do
    title = RecordingResolution::DiscoveryTitle
    credits = [ { "name" => "Charli xcx" }, { "name" => "Sky Ferreira" } ]
    [ " (FEAT. SKY FERREIRA)", " [ft. Sky Ferreira]", " – Featuring Sky Ferreira" ].each do |suffix|
      expect(title.recording_match?("Cross You Out#{suffix}", "Cross You Out", credits)).to be(true)
      expect(title.recording_match?("Cross You Out#{suffix}", "Cross You Out", credits.first(1))).to be(false)
    end
    expect(title.recording_match?("Cross You Out! [ft. Sky Ferreira]", "Cross You Out", credits)).to be(true)
    expect(title.featured_credit("Cross You Out (Live)")).to be_nil
    expect(title.featured_credit("Cross You Out (Live) [ft. Sky Ferreira]")).to eq([ "Cross You Out (Live)", "Sky Ferreira" ])
    expect(title.recording_match?("Cross You Out (Live) [ft. Sky Ferreira]", "Cross You Out", credits)).to be(false)
  end

  it "shares cache entries across key types and order while preserving repeated value order and expiry" do
    notation = WebMock::Config.instance.query_values_notation
    WebMock::Config.instance.query_values_notation = :flat_array
    request = stub_request(:get, "#{base_url}/release?tag=jazz&tag=funk&fmt=json")
      .to_return({ body: '{"value":1}' }, { body: '{"value":2}' })
    freeze_time do
      expect(session.get(:musicbrainz, "/ws/2/release", params: { tag: %w[jazz funk], "fmt" => "json" })["data"]).to eq("value" => 1)
      expect(session.get(:musicbrainz, "/ws/2/release", params: { fmt: "json", "tag" => %w[jazz funk] })["data"]).to eq("value" => 1)
      expect(request).to have_been_requested.once
      travel 1.second
      expect(session.get(:musicbrainz, "/ws/2/release", params: { fmt: "json", tag: %w[funk jazz] })["data"]).to eq("value" => 2)
      expect(request).to have_been_requested.twice
      travel 2.days
      work.update!(lease_until: 2.minutes.from_now)
      session.get(:musicbrainz, "/ws/2/release", params: { fmt: "json", tag: %w[jazz funk] })
      expect(request).to have_been_requested.times(3)
    end
  ensure
    WebMock::Config.instance.query_values_notation = notation
  end

  it "rejects conflicting aliases before provider access and accepts identical aliases" do
    expect do
      session.get(:musicbrainz, "/ws/2/release", params: { fmt: "json", "fmt" => "xml" })
    end.to raise_error(RecordingResolution::ProviderError, /Conflicting query parameter/) { |error| expect(error.terminal).to be(true) }
    expect(work.reload.request_count).to eq(0)

    request = stub_request(:get, "#{base_url}/release?fmt=json").to_return(body: "{}")
    session.get(:musicbrainz, "/ws/2/release", params: { fmt: "json", "fmt" => "json" })
    expect(request).to have_been_requested.once
  end

  it "honors Retry-After on the mixed-key browse and caches only the successful response" do
    request = stub_request(:get, "#{base_url}/release").with(query: group_query).to_return(
      { status: 503, headers: { "Retry-After" => "15" } },
      { status: 200, body: { "release-count" => 0, "release-offset" => 0, "releases" => [] }.to_json })
    freeze_time do
      browse = -> { client.collection_editions(session, NarrowStairsFixture::GROUP, limit: 25) }
      expect(&browse).to raise_error(RecordingResolution::ProviderError) do |error|
        expect(error).to have_attributes(http_status: 503, retry_at: 15.seconds.from_now, terminal: false)
      end
      expect(&browse).to raise_error(RecordingResolution::ProviderError) { |error| expect(error.deferred).to be(true) }
      expect(request).to have_been_requested.once
      travel 15.seconds
      expect(browse.call).to be_empty
      expect(browse.call).to be_empty
      expect(request).to have_been_requested.twice
    end
  end
end
