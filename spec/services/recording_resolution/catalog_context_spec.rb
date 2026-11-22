require "rails_helper"

RSpec.describe RecordingResolution::CatalogContext do
  it "links verified persisted memberships without guessing from a candidate edition" do
    artist = Artist.create!(mbid: SecureRandom.uuid, name: "Canonical artist")
    recording = Recording.create!(mbid: SecureRandom.uuid, title: "Canonical recording")
    recording.recording_artists.create!(artist:, role: :primary)
    edition = SecureRandom.uuid
    unrelated = Release.create!(title: "Unrelated release", ingested_from_release_mbid: edition, catalog_verified_at: Time.current)
    release = Release.create!(title: "Canonical release", ingested_from_release_mbid: SecureRandom.uuid, catalog_verified_at: Time.current)
    release.catalog_track_slots.create!(recording:, medium: 1, position: 1, title: recording.title, track_mbid: SecureRandom.uuid)
    candidate = { "id" => recording.mbid, "artist-credit" => [ { "artist" => { "id" => artist.mbid } } ],
      "releases" => [ { "id" => edition } ] }
    unknown = candidate.merge("id" => SecureRandom.uuid)

    expect {
      context = described_class.new([ candidate, unknown ])
      rows = context.rows(candidate)
      expect(rows.map(&:second)).to eq([ [ artist ], [ recording ], [ release ] ])
      expect(rows.last[1]).not_to include(unrelated)
      expect(context.rows(unknown).map(&:second)).to eq([ [ artist ], [], [] ])
    }.not_to change { [ Artist.count, Recording.count, Release.count ] }
    expect(CanonicalCatalog::Store.recording!(candidate.merge("title" => "Provider caption"))).to eq(recording)
  end
end
