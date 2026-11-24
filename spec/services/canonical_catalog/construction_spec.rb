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
  it "retains checked edition additions as evidence when resolution admits only the selected base recording" do
    us, jp, = guilt_show_editions
    editions = [ us, jp ].map { |edition| CanonicalCatalog::Edition.new(edition, edition.fetch("id")) }
    selected = editions.first.slots.first.dig(:recording, "id")
    bonus = editions.last.slots.last.dig(:recording, "id")
    construction = described_class.new(editions, recording_mbid: selected)

    expect(construction.additional_slots).to be_empty
    expect(construction.appearances.last.fetch("additional_tracks")).to contain_exactly(include("recording_mbid" => bonus))
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

  it "keeps Queen of the Clouds source sequences whole and identifies the genuine divergence at track 16" do
    data = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/construction/queen_of_the_clouds.json").read)
    original, expanded, later = %w[
      9cd3b250-dc88-450f-8836-dbd0e0fa2ccc
      1f21b9a1-0b81-4f3b-8b1b-3ff9e44a91ae
      17e2d704-6ee3-45ad-a494-d92b1d13abcc
    ].map do |id|
      CanonicalCatalog::Edition.new(data.find { |edition| edition.fetch("id") == id }, id)
    end

    expect(CanonicalCatalog::TrackComparison.equivalent_sequence?(original.slots, later.slots)).to be(true)
    expect(CanonicalCatalog::TrackComparison.equivalent_sequence?(original.slots.take(15), expanded.slots.take(15))).to be(true)
    expect(CanonicalCatalog::TrackComparison.compare(original.slots[15], expanded.slots[15])).to eq(:different)
    expect(CanonicalCatalog::TrackComparison.compare(original.slots[15], expanded.slots[16])).to eq(:equivalent)
    expect(described_class.originals([ original, later, expanded ])).to contain_exactly(original, expanded)

    construction = described_class.new([ original, later, expanded ], base: original)
    expect(construction.base.slots).to eq(original.slots)
    expect(construction.additional_slots).to be_empty
    differences = construction.appearances.find { |appearance| appearance["id"] == expanded.data["id"] }
    expect(differences.fetch("competing_sequence_tracks").pluck("title")).to eq(
      [ "Love Ballad", "Over", "Out Of Mind - Bonus Track", "Paradise" ])
  end

  it "groups corroborated alternate source IDs and retains uncertain look-alikes without admitting them" do
    data = narrow_stairs_editions.find { |edition| edition["id"] == NarrowStairsFixture::ORIGINAL }
    track = data.dig("media", 0, "tracks", 2)
    track.fetch("recording")["isrcs"] = [ "USABC0800001" ]
    corroborated = data.deep_dup.merge("id" => SecureRandom.uuid)
    alias_track = corroborated.dig("media", 0, "tracks", 2)
    alias_track["id"] = SecureRandom.uuid
    alias_track.fetch("recording")["id"] = SecureRandom.uuid
    uncertain = corroborated.deep_dup.merge("id" => SecureRandom.uuid, "date" => "2009")
    uncertain_track = uncertain.dig("media", 0, "tracks", 2)
    uncertain_track["id"] = SecureRandom.uuid
    uncertain_track.fetch("recording").merge!("id" => SecureRandom.uuid, "isrcs" => [])
    editions = [ data, corroborated, uncertain ].map { |edition| CanonicalCatalog::Edition.new(edition, edition.fetch("id")) }

    representative = described_class.originals(editions).sole
    expect(representative).to be_in(editions.first(2))
    construction = described_class.new(editions, base: representative)
    expect(construction.base.slots).to eq(representative.slots)
    expect(construction.additional_slots).to be_empty
    expect(construction.appearances.last.fetch("uncertain_tracks")).to contain_exactly(
      include("recording_mbid" => uncertain_track.dig("recording", "id")))
    left = editions.first.slots.third.deep_dup
    right = editions.second.slots.third.deep_dup
    left.fetch(:recording)["disambiguation"] = "clean"
    right.fetch(:recording)["disambiguation"] = "explicit"
    expect(CanonicalCatalog::TrackComparison.compare(left, right)).to eq(:uncertain)
    expect(Recording.count).to eq(0)
  end

  it "verifies the authentic tracklist using source IDs even when a slot points at a different canonical recording" do
    data = narrow_stairs_editions.find { |edition| edition["id"] == NarrowStairsFixture::ORIGINAL }
    track = data.dig("media", 0, "tracks", 2)
    track["length"] = 159_999
    edition = CanonicalCatalog::Edition.new(data, data.fetch("id"))
    request = CatalogImport.create!(kind: "release", entity_id: 1, due_at: Time.current)
    release = CanonicalCatalog::Store.new(request, Struct.new(:provenance).new([])).release(data, edition.slots)
    slot = release.catalog_track_slots.find_by!(track_mbid: track.fetch("id"))
    expect(slot).to have_attributes(source_recording_mbid: track.dig("recording", "id"),
      duration_ms: 159_999, source_artist_credit: track["artist-credit"].presence || track.dig("recording", "artist-credit"))
    slot.update!(recording: Recording.create!(title: "Fixture canonical counterpart", mbid: SecureRandom.uuid))
    evidence = RecordingResolution::ReleaseTracklist.new(release).assessment_fields.fetch("slots").third
    expect(evidence).to include("track_mbid" => track.fetch("id"), "recording_mbid" => track.dig("recording", "id"), "length" => 159_999)
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
