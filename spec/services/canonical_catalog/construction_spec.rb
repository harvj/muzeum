require "rails_helper"
require_relative "../../support/guilt_show_fixture"
require_relative "../../support/narrow_stairs_fixture"


RSpec.describe CanonicalCatalog::Construction do
  include GuiltShowFixture
  include NarrowStairsFixture

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
  it "retrieves all five launch-day Narrow Stairs editions, independently of the recording's 2015 appearance" do
    releases = narrow_stairs_editions
    later = releases.find { |edition| edition["id"] == NarrowStairsFixture::LATER }
    originals = releases.excluding(later)
    provider = double(provenance: [])
    client = instance_double(Clients::Musicbrainz)
    surface = instance_double(RecordingResolution::Surface, album: "Narrow Stairs", artist: "Death Cab for Cutie", track: "No Sunlight")
    expect(client).to receive(:collection_editions).with(provider, NarrowStairsFixture::GROUP, limit: 25).and_return(releases)
    originals.each do |edition|
      expect(client).to receive(:edition).with(provider, edition.fetch("id"), catalog: true).and_return(edition)
    end

    discovery = RecordingResolution::EditionDiscovery.new(client, provider)
    appearances = discovery.call(surface, [], checked: later, attempted: nil, search: false)
    expect(appearances.pluck("id")).to eq([ NarrowStairsFixture::RECORDING ])
    expect(appearances.first.dig("release_discovery", "id")).to eq(NarrowStairsFixture::LATER)
    editions = discovery.construction_editions.map { |id, data| CanonicalCatalog::Edition.new(data, id) }
    expect(described_class.originals(editions).map(&:data).pluck("id")).to eq([ NarrowStairsFixture::ORIGINAL ])
    construction = described_class.new(editions.reverse)
    expect(construction.base.slots.size).to eq(11)
    expect(construction.base.slots.fetch(2).dig(:recording, "id")).to eq(NarrowStairsFixture::RECORDING)
    later_bonus = later.dig("media", 0, "tracks", 12, "recording", "id")
    expect(construction.additional_slots).to include(include(edition_mbid: NarrowStairsFixture::LATER,
      appearance_date: "2015-02-24", recording: include("id" => later_bonus)))
  end

  it "presents material original tracklist conflicts without merging the unselected sequence" do
    data = narrow_stairs_editions.find { |edition| edition["id"] == NarrowStairsFixture::ORIGINAL }
    other = data.deep_dup.merge("id" => SecureRandom.uuid)
    bonus = narrow_stairs_editions.first.dig("media", 0, "tracks", 11).deep_dup
    other.dig("media", 0, "tracks")[1] = bonus.merge("position" => 2, "number" => "2")
    editions = [ data, other ].map { |edition| CanonicalCatalog::Edition.new(edition, edition.fetch("id")) }

    expect(described_class.originals(editions)).to match_array(editions)
    expect { described_class.new(editions) }.to raise_error(CanonicalCatalog::Store::Unverified, /disagree/)
    chosen = described_class.new(editions, base: editions.first)
    expect(chosen.base.data["id"]).to eq(NarrowStairsFixture::ORIGINAL)
    expect(chosen.additional_slots).to be_empty
  end
end
