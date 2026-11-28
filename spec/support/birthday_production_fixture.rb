module BirthdayProductionFixture
  def seed_birthday_review(user)
    fixture = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/release_reviews/birthday-production-history.json").read)
    evidence = fixture.fetch("assessments").last.fetch("evidence")
    payload = evidence.fetch("source_claims").merge("artist_name" => "Blur", "album_name" => "Leisure",
      "track_name" => "Birthday - 2012 Remaster")
    plays = fixture.fetch("observations").map do |observation|
      Scrobble.create!(id: observation.fetch("id"), played_at: observation.fetch("played_at"),
        user:, lastfm_account: user.source_account, payload:)
    end
    surface = RecordingResolution::Ledger.attach!(plays.find { |play| play.id == 293137 })
    group = RecordingResolution::Group.create!(surface_id: surface.id, version: RecordingResolution::Ledger::VERSION,
      claims: payload.slice(*RecordingResolution::PilotRunner::CLAIM_FIELDS))
    fixture.fetch("assessments").each do |snapshot|
      data = snapshot.fetch("evidence")
      RecordingResolution::Assessment.create!(id: snapshot.fetch("id"), group_id: group.id,
        version: snapshot.fetch("version"), created_at: snapshot.fetch("created_at"),
        digest: Digest::SHA256.hexdigest(data.to_json), actor: "fixture", evidence: data)
    end
    if fixture.fetch("assessments").last.fetch("version") != RecordingResolution::Assessment::INTERPRETATION_VERSION
      # Keep the historical snapshots while presenting the current interpretation
      # in browser tests that exercise confirmation without a live provider.
      RecordingResolution::Assessment.create!(id: fixture.fetch("assessments").last.fetch("id") + 1, group_id: group.id,
        version: RecordingResolution::Assessment::INTERPRETATION_VERSION, digest: Digest::SHA256.hexdigest(evidence.to_json),
        actor: "fixture", evidence:)
    end
    [ plays, evidence ]
  end
end
