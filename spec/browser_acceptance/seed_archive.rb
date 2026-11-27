require "json"
require ENV.fetch("MUZEUM_BROWSER_FIXTURE")

abort "Disposable archive database required" unless ENV.fetch("DATABASE_URL").end_with?("/muzeum_browser_acceptance")
fixture = Object.new.extend(PublicProfileFixture).listening_profile_fixture
subject = JSON.parse(File.read(File.join(ENV.fetch("MUZEUM_BROWSER_WORK"), "identity.json"))).fetch("subject").to_s
fixture.fetch(:owner).update!(oidc_subject: subject)
abort "Unexpected fixture publication" if ListeningProfile.published.exists?(id: fixture.fetch(:profile).id)

require Rails.root.join("spec/support/leisure_configurations_fixture")
sources = Object.new.extend(LeisureConfigurationsFixture)
evidence = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/release_reviews/birthday-293137.json").read).fetch("evidence")
research = JSON.parse(Rails.root.join("docs/design/release-configurations/tracklists.json").read)
credits = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/discovery/blur-checked-editions.json").read).first.fetch("artist-credit")
evidence["reviewed_adjacent_programs"] = research.fetch("adjacent_program_editions")
  .select { |edition| edition.fetch("id").start_with?("b11e", "ea3d", "7916") }
  .map do |edition|
    sources.source_edition(edition).tap do |program|
      program["release-group"].merge!("primary-type" => "Single", "first-release-date" => program.fetch("date"))
      program["artist-credit"] = credits
      program["media"].each do |medium|
        medium["tracks"].each { |track| track.fetch("recording")["artist-credit"] = credits }
      end
    end
  end
evidence["reassessment"] = { "checked_at" => "2026-11-27T12:00:00Z" }
owner = fixture.fetch(:owner)
payload = evidence.fetch("source_claims", {}).merge("artist_name" => "Blur",
  "album_name" => "Leisure", "track_name" => "Birthday - 2012 Remaster")
plays = 8.times.map do |offset|
  Scrobble.create!(id: 293137 + offset, user: owner, lastfm_account: owner.source_account,
    played_at: Time.utc(2026, 11, 26) - offset.days, payload:)
end
surface = RecordingResolution::Ledger.attach!(plays.first)
group = RecordingResolution::Group.create!(surface_id: surface.id, version: RecordingResolution::Ledger::VERSION,
  claims: payload.slice(*RecordingResolution::PilotRunner::CLAIM_FIELDS))
RecordingResolution::Assessment.create!(group_id: group.id, version: RecordingResolution::Assessment::INTERPRETATION_VERSION,
  digest: Digest::SHA256.hexdigest(evidence.to_json), actor: "fixture", evidence:)
