require_relative "catalog_fixtures"

module GuiltShowFixture
  def guilt_show_editions
    JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/construction/guilt_show.json").read)
  end

  def guilt_show_assessment(user)
    us, jp, web = guilt_show_editions
    recording = jp.dig("media", 0, "tracks", 13, "recording")
    plays = 3.times.map do |index|
      Scrobble.create!(user:, lastfm_account: user.source_account, played_at: index.hours.ago,
        payload: { artist_name: "The Get Up Kids", album_name: "Guilt Show", track_name: "Like a Man Possessed" })
    end
    surface = RecordingResolution::Ledger.attach!(plays.first)
    group = RecordingResolution::Group.create!(surface_id: surface.id, version: RecordingResolution::Ledger::VERSION, claims: {})
    assessment = RecordingResolution::Assessment.create!(group_id: group.id, version: "construction-fixture", actor: "fixture",
      digest: SecureRandom.hex(32), evidence: {
        "candidates" => [ recording ], "construction_editions" => [ us, jp, web ],
        "review_tracklists" => { jp["id"] => RecordingResolution::ReviewRelease.project(jp) }
      })
    [ plays, assessment, recording, us ]
  end
end
