require "rails_helper"
require_relative "../../support/guilt_show_fixture"


RSpec.describe CanonicalCatalog::Construction do
  include GuiltShowFixture

  it "separates later additional tracks from the original sequence and retains independent date evidence" do
    us, jp, web = guilt_show_editions
    bonus = jp.dig("media", 0, "tracks", 13)

    construction = described_class.new([ jp, web, us ].map { |edition| CanonicalCatalog::Edition.new(edition, edition.fetch("id")) })

    expect(construction.appearances.pluck("id")).not_to include(web["id"])
    expect(construction.base.data["date"]).to eq("2004-03-02")
    expect(construction.base.slots.size).to eq(13)
    expect(construction.appearances.last["track_count"]).to eq(14)
    expect(construction.appearances.last["additional_tracks"]).to contain_exactly(
      include("recording_mbid" => bonus.dig("recording", "id"), "edition_appearance_date" => "2004-08-21",
        "provider_first_release_date" => "2004-06-22")
    )
  end
  it "recovers the original sequence when investigation first finds only the Japanese edition" do
    us, jp, web = guilt_show_editions
    musicbrainz = instance_double(Clients::Musicbrainz)
    provider = double(provenance: [])
    surface = instance_double(RecordingResolution::Surface, album: "Guilt Show", artist: "The Get Up Kids", track: "Like a Man Possessed")
    expect(musicbrainz).to receive(:collection_editions).with(provider, jp.dig("release-group", "id"), limit: 25)
      .and_return([ us, jp, web ])
    expect(musicbrainz).to receive(:edition).with(provider, us["id"], catalog: true).and_return(us)

    discovery = RecordingResolution::EditionDiscovery.new(musicbrainz, provider)
    candidates = discovery.call(surface, [], checked: jp, attempted: nil, search: false)

    expect(candidates.first.dig("release_discovery", "position")).to eq(14)
    expect(discovery.construction_editions.keys).to contain_exactly(us["id"], jp["id"])
  end

end
