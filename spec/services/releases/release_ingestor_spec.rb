require "rails_helper"

RSpec.describe Releases::ReleaseIngestor do
  let(:client) { instance_double(Clients::Musicbrainz) }

  let!(:scrobble) do
    Scrobble.create!(
      played_at: Time.current,
      user: User.create!(lastfm_username: "foo"),
      payload: { track_name: "The Hop" },
      recording_surface: recording_surface
    )
  end

  let!(:recording_surface) do
    RecordingSurface.create!(
      artist_name: "A Tribe Called Quest",
      track_name: "The Hop",
      album_name: "Beats, Rhymes and Life",
      normalized_key: "a tribe called quest||beats, rhymes, and life||the hop",
      release_candidates: [ candidate.to_h ],
      chosen_release_candidate_index: 0
    )
  end

  let(:candidate) do
    ReleaseCandidate.new(
      source: :musicbrainz,
      release_group_mbid: "af2a22ae-15c9-3c73-9a35-7b4f503d8f7c",
      release_group_title: "Beats, Rhymes and Life",
      primary_type: "Album",
      secondary_types: [],
      release_year: 1996,
      release_month: nil,
      release_day: nil,
      country: "US",
      formats: [ "CD" ],
      track_count: 15,
      representative_release_mbid: "f906d3fd-7832-4018-a435-287cd9c50339"
    )
  end

  let(:mb_release_payload) do
    JSON.parse(
      File.read("spec/fixtures/musicbrainz/releases/brl_us_release.json")
    )
  end

  before do
    allow(Clients::Musicbrainz)
      .to receive(:new)
      .and_return(client)

    allow(client)
      .to receive(:fetch_release)
      .with(candidate.representative_release_mbid)
      .and_return(mb_release_payload)
  end

  subject(:ingest!) do
    described_class.call(recording_surface)
  end

  it "creates artists from MB data" do
    expect { ingest! }.to change(Artist, :count).by(2) # ATCQ plus Tammy Lucas as featured artist on one track
  end

  it "creates a release with correct MBIDs" do
    ingest!

    release = Release.last

    expect(release.ingested_from_release_mbid).to eq(candidate.representative_release_mbid)
    expect(release.release_group_mbid).to eq(candidate.release_group_mbid)
  end

  it "creates a full release tracklist" do
    ingest!

    release = Release.last

    expect(release.release_recordings.count).to eq(15)
  end

  it "assigns recording id to scrobble and surface" do
    ingest!

    expect(scrobble.reload.recording).to eq recording_surface.recording
  end

  it "is idempotent" do
    ingest!
    expect { ingest! }.to change { Release.count }.by(0)
  end
end
