module QueenShortTrackFixture
  def queen_short_track_fixture(user)
    episode = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/release_provenance/queen.json").read)
    edition = episode.fetch("construction_editions").find { |item| item["id"] == "9cd3b250-dc88-450f-8836-dbd0e0fa2ccc" }
    release = Release.create!(title: "Queen of the Clouds", release_year: 2014, catalog_verified_at: Time.current,
      ingested_from_release_mbid: edition.fetch("id"), release_group_mbid: edition.dig("release-group", "id"))
    tracks = CanonicalCatalog::Edition.new(edition, edition.fetch("id")).slots.slice(4, 3)
    recordings = tracks.map do |source|
      recording = Recording.create!(mbid: source.fetch(:source_recording_mbid), title: source.fetch(:title), duration_ms: source.fetch(:duration_ms))
      release.catalog_track_slots.create!(source.except(:recording, :number).merge(recording:))
      recording
    end
    first = 2.days.ago.change(usec: 0)
    plays = [ [ recordings.first, first ], [ recordings.last, first + 219.seconds ] ].map do |recording, played_at|
      play = Scrobble.create!(user:, lastfm_account: user.source_account, played_at:, payload: {
        "artist_name" => "Tove Lo", "album_name" => release.title, "track_name" => recording.title
      })
      RecordingResolution::Ledger.record!(listener: user, scrobble: play, scope: :surface,
        mode: "resolved", recording:, reason: "Disposable short-track acceptance")
      play
    end
    [ release, recordings.second, *plays ]
  end
end
