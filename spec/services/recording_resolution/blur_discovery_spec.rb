require "rails_helper"

RSpec.describe "Blur recording evidence" do
  let(:editions) { JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/discovery/blur-checked-editions.json").read) }
  let(:first_day) { editions.find { |edition| edition["id"] == "dc2c22eb-9e48-4caa-8263-87c4cfe40a1a" } }
  let(:remaster) { editions.find { |edition| edition["id"] == "2d855ad9-fbd5-4f73-86a1-949302680df6" } }

  it "recovers both exact first-track identifiers from retained editions when title search is empty or unavailable" do
    [ "-", "–", "—" ].each do |dash|
      title = "She's so High #{dash} 2012 Remaster"
      surface = Struct.new(:artist, :track, :album).new("Blur", title, "Leisure")
      session = double(provenance: [], current_request: { "parameters" => { "query" => "retained query" } })
      expect(session).to receive(:get).with(:musicbrainz, "/ws/2/recording", params: hash_including(query: include(title))).ordered
        .and_raise(RecordingResolution::ProviderError, "Search unavailable")
      expect(session).to receive(:get).with(:musicbrainz, "/ws/2/recording", params: hash_including(query: include("She's so High"))).ordered
        .and_return("data" => { "recordings" => [], "offset" => 0, "count" => 0 })

      evidence = RecordingResolution::Evaluator.new(session, discogs: nil, workspace: true, origins: false,
        retained: [ first_day, remaster ]).call(surface, {})
      expected = [ "3f08ad45-0c00-436e-b737-80c137d4e081", "1c14202a-2ea7-4aff-bc41-6c97eb8a45e8" ]
      ranks = RecordingResolution::Ranking.call(surface, evidence, source_hints: true)
      expect(ranks.pluck("recording_mbid")).to match_array(expected)
      expect(evidence.fetch("candidates").map { |candidate| candidate.dig("release_discovery", "position") }).to eq([ 1, 1 ])
      expect(evidence.dig("title_interpretation", "original_title")).to eq(title)
      expect(evidence.fetch("recording_search_failures").sole.fetch("message")).to eq("Search unavailable")
      expect(evidence).not_to have_key("suggested_mbid")
      expect(RecordingResolution::Ranking.recommended?(ranks)).to be_falsey
    end
  end

  it "does not promote an old mispressing history into an original album proposal" do
    id = "a4f6872f-ff57-476c-8897-3ddc52d2169b"
    assessment = double(evidence: { "construction_editions" => editions,
      "recording_publications" => { id => { "original_groups" => editions.map { |edition| edition.dig("release-group", "id") }.uniq } } })
    contexts = CanonicalCatalog::ReviewedConstruction.for(assessment, id)
    expect(contexts.map { |proposal| proposal.construction.base.data["id"] }).to eq([ first_day["id"] ])
    expect(contexts.sole.construction.base.slots.last).to include(position: 12, source_recording_mbid: id)
    provenance = RecordingResolution::ReleaseProvenance.new(assessment.evidence, contexts:, releases: [], recording_mbid: id)
    source, slots = provenance.other_recording_appearances.sole
    expect(source).to include("id" => "12625b09-8ea4-46d8-b4e3-b916e819e039", "disambiguation" => "mispressing")
    expect(slots.sole).to include(position: 14, source_recording_mbid: id)
  end
end
