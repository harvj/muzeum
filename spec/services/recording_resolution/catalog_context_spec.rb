require "rails_helper"

RSpec.describe RecordingResolution::CatalogContext do
  it "independently links each exact stored identity without creating or guessing entities" do
    artist = Artist.create!(mbid: SecureRandom.uuid, name: "Canonical artist")
    recording = Recording.create!(mbid: SecureRandom.uuid, title: "Canonical recording")
    edition = SecureRandom.uuid
    release = Release.create!(title: "Canonical release", ingested_from_release_mbid: edition, catalog_verified_at: Time.current)
    candidate = { "id" => recording.mbid, "artist-credit" => [ { "artist" => { "id" => artist.mbid } } ],
      "releases" => [ { "id" => edition } ] }
    ambiguous = candidate.merge("artist-credit" => [ *candidate["artist-credit"], { "artist" => { "id" => SecureRandom.uuid } } ])
    expect {
      context = described_class.new([ candidate, ambiguous ], {})
      expect(context.rows(candidate, edition).map(&:second)).to eq([ artist, recording, release ])
      expect(context.rows(ambiguous, SecureRandom.uuid).map(&:second)).to eq([ nil, recording, nil ])
    }.not_to change { [ Artist.count, Recording.count, Release.count ] }
    expect(CanonicalCatalog::Store.recording!(candidate.merge("title" => "Provider caption"))).to eq(recording)
  end
end
