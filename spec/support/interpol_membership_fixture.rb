module InterpolMembershipFixture
  BASE = "18484ef2-8dc4-30b1-8618-85950a374b1d"
  JAPAN = "f4e04c18-2354-4362-a9db-c27753dd1717"
  BONUS = "2c1174e2-988b-484f-bfc9-c247cf9e46c5"

  def interpol_membership_fixture(user)
    editions = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/release_provenance/interpol-membership.json").read)
    japanese = editions.find { |edition| edition["id"] == JAPAN }
    bonus = japanese.dig("media", 0, "tracks").find { |track| track.dig("recording", "id") == BONUS }.fetch("recording")
    play = Scrobble.create!(user:, lastfm_account: user.source_account, played_at: Time.current,
      payload: { artist_name: "Interpol", track_name: "Mind Over Time", album_name: "Our Love to Admire" })
    surface = RecordingResolution::Ledger.attach!(play)
    group = RecordingResolution::Group.create!(surface_id: surface.id, version: RecordingResolution::Ledger::VERSION, claims: {})
    group_id = japanese.dig("release-group", "id")
    assessment = RecordingResolution::Assessment.create!(group_id: group.id, version: "fixture", actor: "fixture",
      digest: SecureRandom.hex(32), evidence: { "candidates" => [ bonus ], "construction_editions" => editions,
        "recording_publications" => { BONUS => { "original_groups" => [ group_id ] } } })
    [ play, assessment ]
  end
end
