module NarrowStairsFixture
  ORIGINAL = "7c34970e-b509-4a59-aace-da8927ff1f4b"
  LATER = "0a89047d-bb9d-413d-acc3-5f0b6b37291b"
  RECORDING = "e77221ef-5081-41cc-96ce-c0f72c540d13"
  GROUP = "9b95d445-2293-366e-8e45-6fde0aa4f1d2"

  def narrow_stairs_editions
    JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/construction/narrow_stairs.json").read)
  end

  def narrow_stairs_assessment(user, historical: false)
    editions = narrow_stairs_editions
    later = editions.find { |edition| edition["id"] == LATER }
    recording = later.dig("media", 0, "tracks", 2, "recording")
    observation = Scrobble.create!(user:, lastfm_account: user.source_account, played_at: Time.current,
      payload: { artist_name: "Death Cab for Cutie", album_name: "Narrow Stairs", track_name: "No Sunlight" })
    surface = RecordingResolution::Ledger.attach!(observation)
    group = RecordingResolution::Group.create!(surface_id: surface.id, version: RecordingResolution::Ledger::VERSION, claims: {})
    assessment = RecordingResolution::Assessment.create!(group_id: group.id, version: "construction-fixture", actor: "fixture",
      digest: SecureRandom.hex(32), evidence: {
        "candidates" => [ recording.merge("releases" => [ later.slice("id", "title", "date", "country") ]) ],
        "construction_editions" => historical ? [] : editions,
        "review_tracklists" => { LATER => RecordingResolution::ReviewRelease.project(later) }
      })
    [ observation, assessment ]
  end
end
