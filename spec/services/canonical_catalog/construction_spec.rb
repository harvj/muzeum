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
    expect(construction.additional_slots).to be_empty
    expect(construction.additional_tracks.flatten).to include(
      include("recording_mbid" => later_bonus, "edition_mbid" => NarrowStairsFixture::LATER,
        "edition_appearance_date" => "2015-02-24"))
    reviewed = described_class.new(editions.reverse, recording_mbid: later_bonus)
    expect(reviewed.additional_slots).to include(include(edition_mbid: NarrowStairsFixture::LATER,
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

    expect(described_class.selectable_bases([ original, later, expanded ])).to contain_exactly(original, later, expanded)
    expect(described_class.new([ original, later, expanded ], base: later).base.slots).to eq(later.slots)
    worldwide = described_class.new([ original, later, expanded ], base: expanded)
    expect(worldwide.base.slots).to eq(expanded.slots)
    expect(worldwide.additional_tracks).to be_empty

    construction = described_class.new([ original, later, expanded ], base: original)
    expect(construction.base.slots).to eq(original.slots)
    expect(construction.additional_slots).to be_empty
    differences = construction.appearances.find { |appearance| appearance["id"] == expanded.data["id"] }
    expect(differences.fetch("additional_tracks").pluck("title")).to eq(
      [ "Love Ballad", "Over", "Out Of Mind - Bonus Track", "Paradise" ])
  end

  it "keeps the other audited Queen launch editions as evidence beyond the two original programs" do
    base = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/construction/queen_of_the_clouds.json").read)
    extensions = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/construction/queen_of_the_clouds_launch_extensions.json").read)
    editions = (base + extensions).map { |data| CanonicalCatalog::Edition.new(data, data.fetch("id")) }
    originals = described_class.originals(editions)
    expect(originals.map { |edition| edition.slots.size }).to contain_exactly(16, 20)
    expect(described_class.selectable_bases(editions).map(&:data).pluck("id")).to match_array(base.pluck("id"))
    worldwide = originals.find { |edition| edition.slots.size == 20 }
    additions = described_class.new(editions, base: worldwide).additional_tracks.map { |group| group.first.fetch("title") }
    expect(additions).to contain_exactly("Not Made for This World", "Not on Drugs (Ali Payami remix)")
  end

  it "keeps the production vinyl remix out of both base editions’ additional tracks" do
    fixtures = Rails.root.join("spec/fixtures/musicbrainz/construction")
    data = %w[queen_of_the_clouds queen_of_the_clouds_launch_extensions].flat_map do |name|
      JSON.parse(fixtures.join("#{name}.json").read)
    end
    vinyl = JSON.parse(fixtures.join("queen_of_the_clouds_vinyl.json").read)
    isrcs = JSON.parse(fixtures.join("queen_of_the_clouds_remix_isrcs.json").read)
    source, alternate = isrcs.keys

    [ false, true ].each do |with_isrcs|
      sources = [ *data, vinyl ].deep_dup
      sources.each do |edition|
        edition.fetch("media").flat_map { |medium| medium.fetch("tracks") }.each do |track|
          recording = track.fetch("recording")
          recording["isrcs"] = isrcs.fetch(recording.fetch("id")) if with_isrcs && isrcs.key?(recording.fetch("id"))
        end
      end
      editions = sources.map { |edition| CanonicalCatalog::Edition.new(edition, edition.fetch("id")) }
      vinyl_edition = editions.last
      vinyl_remix = vinyl_edition.slots.find { |track| track[:source_recording_mbid] == alternate }
      described_class.selectable_bases(editions).each do |base|
        source_slots = base.slots.map { |slot| slot.values_at(:medium, :position, :number, :track_mbid, :source_recording_mbid) }
        fingerprint = Digest::SHA256.hexdigest(base.slots.map { |slot| slot.values_at(:medium, :position, :source_recording_mbid) }.to_json)
        base_remix = base.slots.find { |track| track[:source_recording_mbid] == source }
        comparison = CanonicalCatalog::TrackComparison
        expect(comparison.compare(base_remix, vinyl_remix)).to eq(with_isrcs ? :equivalent : :uncertain)

        construction = described_class.new(editions, base:)
        expected = [ "Not Made for This World", "Not on Drugs (Ali Payami remix)", "Not on Drugs (The Knocks remix)" ]
        expected += [ "Love Ballad", "Over", "Out Of Mind - Bonus Track", "Paradise" ] if base.slots.size == 16
        expect(construction.additional_tracks.map { |group| group.first.fetch("title") }).to match_array(expected)
        expect(construction.additional_slots.pluck(:source_recording_mbid)).not_to include(alternate)
        expect(construction.base.slots.map { |slot| slot.values_at(:medium, :position, :number, :track_mbid, :source_recording_mbid) }).to eq(source_slots)
        expect(Digest::SHA256.hexdigest(construction.base.slots.map do |slot|
          slot.values_at(:medium, :position, :source_recording_mbid)
        end.to_json)).to eq(fingerprint)

        next unless with_isrcs

        other_version = vinyl_remix.deep_dup
        other_version.fetch(:recording)["disambiguation"] = "live"
        expect(comparison.compare(base_remix, other_version)).to eq(:uncertain)
        other_title = vinyl_remix.deep_dup
        other_title.fetch(:recording)["title"] = "Habits (Stay High) (another remix)"
        expect(comparison.compare(base_remix, other_title)).to eq(:uncertain)
        other_credit = vinyl_remix.deep_dup
        other_credit.fetch(:recording).fetch("artist-credit").first.fetch("artist")["id"] = SecureRandom.uuid
        expect(comparison.compare(base_remix, other_credit)).to eq(:uncertain)
      end
    end
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
    plausible = uncertain.deep_dup.merge("date" => data["date"])
    alternative = CanonicalCatalog::Edition.new(plausible, plausible.fetch("id"))
    proposals = [ representative, alternative ].map { |base| double(construction: double(base:)) }
    expect(ApplicationController.helpers.resolution_edition_options(proposals).map(&:first)).to all(include("Source recording identity needs review"))
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

  it "keys equivalent album sources by exact ordered slots and musical annotations" do
    data = narrow_stairs_editions.find { |edition| edition["id"] == NarrowStairsFixture::ORIGINAL }
    source = CanonicalCatalog::Edition.new(data, data.fetch("id"))
    comparison = CanonicalCatalog::ConfigurationEvidence
    regional = data.deep_dup.merge("id" => SecureRandom.uuid, "country" => "CA", "barcode" => "012345",
      "disambiguation" => "indie exclusive")
    key = ->(edition) { comparison.key(CanonicalCatalog::Edition.new(edition, edition.fetch("id"))) }
    expect(key.call(regional)).to eq(comparison.key(source))

    expect(key.call(regional.merge("disambiguation" => "Dolby Atmos mix"))).not_to eq(comparison.key(source))
    regional.dig("media", 0)["position"] = 2
    split = CanonicalCatalog::Edition.new(regional, regional.fetch("id"))
    expect(comparison.key(split)).not_to eq(comparison.key(source))
    expect(CanonicalCatalog::TrackComparison.equivalent_sequence?(source.slots, split.slots)).to be(false)
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
