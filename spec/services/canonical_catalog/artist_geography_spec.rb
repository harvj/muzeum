require "rails_helper"
require_relative "../../support/artist_geography_fixture"

RSpec.describe CanonicalCatalog::ArtistGeography do
  include ArtistGeographyFixture
  include ActiveSupport::Testing::TimeHelpers

  it "verifies Boards of Canada and Wilco with the actual constituent and city flags" do
    session = ArtistGeographyFixture::Session.new
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    boards = artist_origin(ArtistGeographyFixture::BOARDS, "Q722778", "GB", session:)
    wilco = artist_origin(ArtistGeographyFixture::WILCO, "Q637771", "US", session:)
    elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1_000

    expect(boards).to include("status" => "verified")
    expect(boards.fetch("hierarchy").pluck("label")).to eq([ "Scotland", "United Kingdom" ])
    expect(boards.dig("founding_location", "label")).to eq("Edinburgh")
    expect(boards.dig("origin", "flag", "url")).to end_with("/Flag_of_Scotland.svg")
    expect(wilco.fetch("hierarchy").pluck("label")).to eq([ "Chicago", "Illinois", "United States" ])
    expect(wilco.dig("origin", "flag", "url")).to end_with("/Flag_of_Chicago%2C_Illinois.svg")
    expect(wilco.dig("origin", "flag", "license")).to eq("Public domain")
    expect(session.provenance.pluck("provider").tally).to eq("wikidata" => 8, "commons" => 2)
    warn format("Two captured Wikimedia artist replays: %.2f ms", elapsed) if ENV["MEASURE_WIKIMEDIA"]
  end

  it "handles the other UK constituent nations from provider statements" do
    { "Q21" => "England", "Q25" => "Wales", "Q26" => "Northern Ireland" }.each do |id, label|
      session = ArtistGeographyFixture::Session.new
      records = session.fixture.fetch("entities")
      records.dig("Q722778", "claims", "P740", 0, "mainsnak", "datavalue", "value")["id"] = id
      result = artist_origin(ArtistGeographyFixture::BOARDS, "Q722778", "GB", session:)
      expect(result.dig("origin", "label")).to eq(label)
      expect(result.dig("country", "label")).to eq("United Kingdom")
    end
  end

  it "retains conflicting formation statements and withholds a specific origin" do
    session = ArtistGeographyFixture::Session.new
    claims = session.fixture.dig("entities", "Q722778", "claims", "P740")
    claims << claims.first.deep_dup
    claims.last.dig("mainsnak", "datavalue", "value")["id"] = "Q1297"

    result = artist_origin(ArtistGeographyFixture::BOARDS, "Q722778", "GB", session:)
    expect(result.fetch("status")).to eq("conflicting")
    expect(result.dig("artist", "claims", "P740").pluck("value")).to eq(%w[Q23436 Q1297])
    expect(result).not_to have_key("origin")
  end

  it "keeps provenance for missing statements and refuses name-only or invalid links" do
    session = ArtistGeographyFixture::Session.new
    session.fixture.dig("entities", "Q722778", "claims").delete("P740")
    expect(artist_origin(ArtistGeographyFixture::BOARDS, "Q722778", "GB", session:).fetch("status")).to eq("incomplete")
    expect(artist_origin(ArtistGeographyFixture::WILCO, "Q722778", "US", session:).fetch("status")).to eq("unverified_identity")
    expect { artist_origin(ArtistGeographyFixture::BOARDS, "../Q722778", "GB", session:) }.to raise_error(ArgumentError)
  end

  it "keeps a verified location when its exact flag cannot be verified" do
    session = ArtistGeographyFixture::Session.new
    session.fixture.dig("commons", "query", "pages").reject! { |page| page["title"].include?("Chicago") }
    result = artist_origin(ArtistGeographyFixture::WILCO, "Q637771", "US", session:)
    expect(result.fetch("origin")).to eq("id" => "Q1297", "label" => "Chicago")
  end

  it "honors maxlag, shares fresh cache, and refreshes expired evidence" do
    path = "https://www.wikidata.org/w/api.php"
    query = { action: "wbgetentities", ids: "Q722778", props: "claims|labels|info", languages: "en", maxlag: 5, format: "json" }
    data = ArtistGeographyFixture::Session.new.fixture.fetch("entities").slice("Q722778")
    upstream = stub_request(:get, path).with(query:, headers: { "User-Agent" => /Muzeum/ }).to_return(
      { status: 200, headers: { "Retry-After" => "15" }, body: { error: { code: "maxlag" } }.to_json },
      { status: 200, body: { entities: data }.to_json })
    token = SecureRandom.uuid
    work = CatalogImport.create!(kind: "artist_geography", entity_id: 1, state: "refreshing", due_at: Time.current,
      lease_token: token, lease_until: 2.minutes.from_now)
    client = Clients::Wikimedia.new(RecordingResolution::ProviderSession.new(work, token, catalog: true))
    request = -> { client.entities([ "Q722778" ], properties: [ "P434" ]) }

    expect(&request).to raise_error(RecordingResolution::ProviderError, /replication lag/)
    expect(&request).to raise_error(RecordingResolution::ProviderError, /deferred/)
    travel 16.seconds do
      expect(request.call.keys).to eq([ "Q722778" ])
      expect(request.call.keys).to eq([ "Q722778" ])
      expect(upstream).to have_been_requested.twice
    end
    travel 8.days do
      work.update!(lease_until: 2.minutes.from_now)
      expect(request.call.keys).to eq([ "Q722778" ])
    end
    expect(upstream).to have_been_requested.times(3)
  end

  it "chains independent worker requests and retains Wikimedia evidence without replacing MusicBrainz fields" do
    artist = Artist.create!(mbid: ArtistGeographyFixture::BOARDS, name: "Boards of Canada", country: "GB")
    original = CatalogImport.request!("artist", artist.id)
    session = ArtistGeographyFixture::Session.new
    run = ->(request) { CanonicalCatalog::Processor.new(request, session_factory: ->(*) { session }).call }
    run.call(original)
    geography = CatalogImport.find_by!(kind: "artist_geography", entity_id: artist.id)
    run.call(geography)

    expect(artist.reload.country).to eq("GB")
    expect(original.reload.state).to eq("imported")
    expect(geography.reload.state).to eq("imported")
    expect(CatalogRevision.find_by!(catalog_import: geography).evidence.dig("origin", "label")).to eq("Scotland")
  end
end
