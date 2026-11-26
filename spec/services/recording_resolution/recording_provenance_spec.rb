require "rails_helper"

RSpec.describe RecordingResolution::RecordingProvenance do
  let(:evidence) do
    JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/release_provenance/interpol.json").read)
  end
  let(:edition) { evidence.fetch("construction_editions").find { |row| row["id"].start_with?("90a206e9") } }
  let(:mbid) { "d0be890e-d883-42eb-8022-e14afee093e1" }
  let(:base) { "17241ce7-07c6-4de9-a5af-822cf2b61000" }
  let(:work) { "bbc630a4-1b0a-4714-bd42-0a331b4f2694" }
  let(:client) { instance_double(Clients::Musicbrainz) }
  let(:session) { instance_double(RecordingResolution::ProviderSession) }
  let(:check) { described_class.new(client, session) }

  before { allow(client).to receive(:provenance_release_group).and_return(nil) }

  it "verifies the instrumental's shared work while preserving its separate recording and exact CD-R placement" do
    instrumental = { "id" => mbid, "relationships" => [
      { "type" => "performance", "target_type" => "work", "target" => { "id" => work }, "attributes" => [ "instrumental" ] }
    ] }
    studio = { "id" => base, "isrcs" => [ "USCA20703929" ], "relationships" => [
      { "type" => "performance", "target_type" => "work", "target" => { "id" => work } }
    ] }
    expect(RecordingResolution::ReleaseProvenance.possible_counterparts(evidence, mbid)).to include(base)
    allow(client).to receive(:provenance_recording).with(session, mbid).and_return(instrumental)
    allow(client).to receive(:provenance_recording).with(session, base).and_return(studio)
    allow(client).to receive(:provenance_releases).with(session, mbid).and_return([ edition.except("media") ])

    history = check.call(mbid, retained: [ edition ], counterparts: [ base ])
    expect(history).to include("classification" => "alternate", "browse_complete" => true, "incomplete" => false)
    expect(history.fetch("exact_recording").fetch("id")).to eq(mbid)
    expect(history.fetch("related_recordings").sole.fetch("id")).to eq(base)
    expect(history.fetch("releases").sole.fetch("slots").sole).to include("medium" => 2, "position" => 7)
  end

  it "retains verified appearances when pagination fails and leaves title-only counterparts unclassified" do
    allow(client).to receive(:provenance_recording).with(session, mbid).and_return({ "id" => mbid })
    allow(client).to receive(:provenance_recording).with(session, base).and_return({ "id" => base })
    allow(client).to receive(:provenance_releases).with(session, mbid) do |*_, &progress|
      progress.call([ edition.except("media") ])
      raise CanonicalCatalog::Store::Unverified, "Evidence budget exhausted"
    end

    history = check.call(mbid, retained: [ edition ], counterparts: [ base ])
    expect(history).to include("classification" => "unclassified", "browse_complete" => false, "incomplete" => true)
    expect(history.fetch("releases").sole).to include("id" => edition["id"])
    expect(history.fetch("earliest_publication")).to include("date" => "2007")
  end

  it "keeps linked Wikidata and Wikipedia release context separate from exact MusicBrainz identity" do
    japan_id = "f4e04c18-2354-4362-a9db-c27753dd1717"
    editions = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/release_provenance/interpol-membership.json").read)
    japan = editions.find { |source| source["id"] == japan_id }
    title = "Mind Over Time"
    recording = japan.dig("media", 0, "tracks").find { |track| track["title"] == title }.fetch("recording")
    id = recording.fetch("id")
    group = japan.fetch("release-group").merge("wikidata_ids" => [ "Q1422991" ])
    allow(client).to receive(:provenance_recording).with(session, id).and_return(recording)
    allow(client).to receive(:provenance_releases).with(session, id).and_return([ japan.except("media") ])
    expect(client).to receive(:provenance_release_group).with(session, group["id"]).and_return(group)
    wikimedia = instance_double(Clients::Wikimedia)
    allow(Clients::Wikimedia).to receive(:new).with(session).and_return(wikimedia)
    expect(wikimedia).to receive(:entities).with([ "Q1422991" ], properties: anything, editorial: true)
      .and_return("Q1422991" => { "english_article" => "Our Love to Admire" })
    notes = [ { "heading" => "Japanese edition bonus tracks", "url" => "https://en.wikipedia.org/w/index.php?oldid=123" } ]
    expect(wikimedia).to receive(:edition_notes).with("Our Love to Admire", title).and_return(notes)

    history = check.call(id, retained: [ japan ], counterparts: [])
    expect(history.dig("supplementary_context", "editorial_edition_notes", group["id"])).to eq(notes)
    expect(history.fetch("exact_recording").fetch("id")).to eq(id)
    expect(history.fetch("releases").sole.fetch("slots").sole.fetch("position")).to eq(12)
    expect(history.fetch("classification")).to eq("unclassified")
  end

  it "paginates exact release results across groups and retains the accepted pages" do
    provider = Clients::Musicbrainz.new
    another = edition.merge("id" => "05116e23-1594-3c23-b050-01e7fea62e1f",
      "release-group" => { "id" => "9a2b8f98-b5c5-3d15-b959-90887ca0050d" })
    path = "/ws/2/release"
    pages = []
    allow(session).to receive(:get).with(:musicbrainz, path, params: hash_including(recording: mbid, limit: 25)) do |_, _, params:, &project|
      offset = params.fetch(:offset, 0)
      row = [ edition, another ].fetch(offset)
      { "data" => project.call("release-count" => 2, "release-offset" => offset, "releases" => [ row ]) }
    end

    result = provider.provenance_releases(session, mbid) { |page| pages << page.pluck("id") }
    expect(result.pluck("id")).to eq([ edition["id"], another["id"] ])
    expect(pages).to eq([ [ edition["id"] ], [ edition["id"], another["id"] ] ])
    expect(result.map { |row| row.dig("release-group", "id") }.uniq.size).to eq(2)
  end
end
