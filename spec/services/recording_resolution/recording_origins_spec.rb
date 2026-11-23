require "rails_helper"
require_relative "../../support/narrow_stairs_fixture"
require_relative "../../support/guilt_show_fixture"

RSpec.describe RecordingResolution::RecordingOrigins do
  include NarrowStairsFixture
  include GuiltShowFixture

  let(:provider) { double(provenance: []) }
  let(:client) { instance_double(Clients::Musicbrainz) }

  def checked_history(ids, browse, editions)
    allow(client).to receive(:verify_recording).with(provider, anything, catalog: true) { |_, id| { "data" => { "id" => id } } }
    allow(client).to receive(:recording_releases).with(provider, anything, limit: 25) { |_, id| browse.fetch(id) }
    allow(client).to receive(:collection_editions).with(provider, anything, limit: 25) do |_, group|
      editions.select { |data| data.dig("release-group", "id") == group }
    end
    allow(client).to receive(:edition).with(provider, anything, catalog: true) { |_, id| editions.find { |row| row["id"] == id } }
    described_class.new(client, provider).call(ids, retained: editions.reverse.first(1))
  end

  it "keeps the real distinct compilation MBID separate and discovers the original album from the recording browse" do
    fixture = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/construction/narrow_stairs_recordings.json").read)
    album_recording = NarrowStairsFixture::RECORDING
    compilation_recording = "5dffd281-d913-4256-8816-7035d077183f"
    editions = narrow_stairs_editions
    browse = fixture.transform_values do |rows|
      rows.select { |row| row.dig("release-group", "id") == NarrowStairsFixture::GROUP || [ "Time Warner 2", "Indie/Rock Playlist: November 2008" ].include?(row["title"]) }
    end
    [ browse, browse.transform_values(&:reverse) ].each do |set|
      evidence = checked_history([ compilation_recording, album_recording ], set, editions)
      history = evidence.fetch("recording_publications")
      expect(history.dig(compilation_recording, "original_groups")).to be_empty
      expect(history.dig(compilation_recording, "earliest_publication", "date")).to eq("2009")
      expect(history.dig(album_recording, "original_groups")).to eq([ NarrowStairsFixture::GROUP ])
      expect(history.dig(album_recording, "earliest_publication", "date")).to eq("2008-05-13")
      expect(history.dig(album_recording, "appearances").pluck("title")).to include("Indie/Rock Playlist: November 2008")
      expect(history.dig(album_recording, "appearances").pluck("id")).to include(NarrowStairsFixture::LATER, NarrowStairsFixture::ORIGINAL)
      assessment = double(evidence:)
      proposal = CanonicalCatalog::ReviewedConstruction.for(assessment, album_recording).sole
      expect(proposal.construction.base.data["id"]).to eq(NarrowStairsFixture::ORIGINAL)
      expect(proposal.construction.base.slots.size).to eq(11)
      expect(proposal.construction.base.slots.third.dig(:recording, "id")).to eq(album_recording)
      expect(proposal.construction.additional_slots).to be_empty
    end
  end

  it "keeps a verified earlier single date separate from the original album date" do
    editions = narrow_stairs_editions
    recording = NarrowStairsFixture::RECORDING
    album = editions.find { |row| row["id"] == NarrowStairsFixture::ORIGINAL }
    track = album.dig("media", 0, "tracks", 2)
    single = album.merge("id" => SecureRandom.uuid, "title" => "Earlier single", "date" => "2008-04",
      "release-group" => { "id" => SecureRandom.uuid, "primary-type" => "Single", "title" => "Earlier single", "first-release-date" => "2008-04" },
      "media" => [ { "position" => 1, "track-count" => 1, "tracks" => [ track.merge("position" => 1) ] } ])
    history = checked_history([ recording ], { recording => [ single, album ] }, editions + [ single ])
    publication = history.fetch("recording_publications").fetch(recording)
    expect(publication.dig("earliest_publication", "date")).to eq("2008-04")
    expect(publication["original_groups"]).to contain_exactly(NarrowStairsFixture::GROUP, single.dig("release-group", "id"))
    expect(CanonicalCatalog::ReviewedConstruction.for(double(evidence: history), recording).map { |proposal| proposal.construction.base.data["date"] })
      .to contain_exactly("2008-04", "2008-05-13")
  end

  it "keeps Guilt Show at 13 base tracks and admits the Japanese addition only when that recording is selected" do
    us, jp, = guilt_show_editions
    original = us.dig("media", 0, "tracks", 0, "recording", "id")
    addition = jp.dig("media", 0, "tracks", 13, "recording", "id")
    evidence = checked_history([ original, addition ], { original => [ us, jp ], addition => [ jp ] }, [ us, jp ])
    assessment = double(evidence:)
    expect(CanonicalCatalog::ReviewedConstruction.for(assessment, original).sole.construction.additional_slots).to be_empty
    proposal = CanonicalCatalog::ReviewedConstruction.for(assessment, addition).sole
    expect(proposal.construction.base.slots.size).to eq(13)
    expect(proposal.construction.additional_slots.sole).to include(position: 14, appearance_date: "2004-08-21")
  end

  it "does not mistake an incomplete browse for a complete recording history" do
    id = NarrowStairsFixture::RECORDING
    client = Clients::Musicbrainz.new
    allow(client).to receive(:verify_recording).with(provider, id, catalog: true).and_return("data" => { "id" => id })
    params = { fmt: "json", recording: id, inc: "release-groups+media", limit: 25 }
    row = narrow_stairs_editions.first
    expect(provider).to receive(:get).with(:musicbrainz, "/ws/2/release", params:) do |*_, &project|
      { "data" => project.call("release-count" => 2, "release-offset" => 0, "releases" => [ row ]) }
    end
    expect(provider).to receive(:get).with(:musicbrainz, "/ws/2/release", params: params.merge(offset: 1)) do |*_, &project|
      { "data" => project.call("release-count" => 2, "release-offset" => 1, "releases" => []) }
    end
    evidence = described_class.new(client, provider).call([ id ], retained: [])
    expect(evidence["recording_publications"]).to eq(id => { "pending" => true })
  end

  it "uses the actual result count as the next browse offset" do
    id = NarrowStairsFixture::RECORDING
    params = { fmt: "json", recording: id, inc: "release-groups+media", limit: 25 }
    first, second, third = narrow_stairs_editions
    expect(provider).to receive(:get).with(:musicbrainz, "/ws/2/release", params:) do |*_, &project|
      { "data" => project.call("release-count" => 3, "release-offset" => 0, "releases" => [ first, second ]) }
    end
    expect(provider).to receive(:get).with(:musicbrainz, "/ws/2/release", params: params.merge(offset: 2)) do |*_, &project|
      { "data" => project.call("release-count" => 3, "release-offset" => 2, "releases" => [ third ]) }
    end

    expect(Clients::Musicbrainz.new.recording_releases(provider, id, limit: 25).pluck("id")).to eq([ first, second, third ].pluck("id"))
  end

  it "lets an HTTP 503 reach the existing worker retry instead of fabricating an original" do
    id = NarrowStairsFixture::RECORDING
    allow(client).to receive(:verify_recording).with(provider, id, catalog: true).and_return("data" => { "id" => id })
    allow(client).to receive(:recording_releases).with(provider, id, limit: 25)
      .and_raise(RecordingResolution::ProviderError.new("musicbrainz throttled (503)", http_status: 503, retry_at: 1.minute.from_now))
    expect do
      described_class.new(client, provider).call([ id ], retained: narrow_stairs_editions)
    end.to raise_error(RecordingResolution::ProviderError, /503/)
  end
end
