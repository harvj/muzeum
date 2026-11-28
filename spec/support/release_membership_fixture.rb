module ReleaseMembershipFixture
  CASES = [
    { id: 293209, assessment: "crash", file: "crash", artist: "Charli xcx", track: "Crash", album: "Crash",
      position: 1, observations: 19, tracks: 12, competing: "ddf851bb-16ed-465b-9714-3451ce7dbc36" },
    { id: 293210, assessment: "heartland", file: "jeopardy", artist: "The Sound", track: "Heartland", album: "Jeopardy",
      position: 2, observations: 4, tracks: 11, competing: "06b2fc47-c2ac-4ad9-a213-f24fa6e1a49d" }
  ].freeze

  def seed_release_membership_case(user, example)
    fixture = Rails.root.join("spec/fixtures/musicbrainz/release_membership")
    edition = JSON.parse(fixture.join("#{example[:file]}.json").read)
    historical = JSON.parse(fixture.join("#{example[:assessment]}-assessment.json").read)
    claims = historical.fetch("source_claims")
    payload = claims.merge("artist_name" => example[:artist], "album_name" => example[:album], "track_name" => example[:track])
    plays = Array.new(example[:observations]) do |index|
      id = example[:id] + (index.zero? ? 0 : index * 10)
      Scrobble.create!(id:, user:, lastfm_account: user.source_account, payload:, played_at: Time.utc(2026, 11, 25) - index.minutes)
    end
    surface = RecordingResolution::Ledger.attach!(plays.first)
    group = RecordingResolution::Group.create!(surface_id: surface.id, claims:, version: RecordingResolution::Ledger::VERSION)
    previous = RecordingResolution::Assessment.create!(group_id: group.id, version: "workspace-evidence-v3",
      digest: Digest::SHA256.hexdigest(historical.to_json), actor: "fixture", evidence: historical)

    studio = edition.fetch("media").first.fetch("tracks").find { |slot| slot["position"] == example[:position] }.fetch("recording")
    editions = [ edition, *Array(historical["construction_editions"]) ].index_by { |row| row.fetch("id") }
    refs = editions.values.map { |row| row.except("media") }
    provider = DiscoveryReplay::Session.new(
      { "releases" => editions, "collections" => { edition.dig("release-group", "id") => refs },
        "recording_releases" => { studio.fetch("id") => refs }, "searches" => {} },
      { "candidates" => historical.fetch("candidates"), "verified_recording" => studio, "release_search" => "unused" })
    [ plays, previous, edition, studio, provider ]
  end
end
