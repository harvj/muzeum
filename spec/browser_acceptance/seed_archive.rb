require "json"
require ENV.fetch("MUZEUM_BROWSER_FIXTURE")

abort "Disposable archive database required" unless ENV.fetch("DATABASE_URL").end_with?("/muzeum_browser_acceptance")
fixture = Object.new.extend(PublicProfileFixture).listening_profile_fixture
subject = JSON.parse(File.read(File.join(ENV.fetch("MUZEUM_BROWSER_WORK"), "identity.json"))).fetch("subject").to_s
fixture.fetch(:owner).update!(oidc_subject: subject)
abort "Unexpected fixture publication" if ListeningProfile.published.exists?(id: fixture.fetch(:profile).id)

require Rails.root.join("spec/support/birthday_production_fixture")
owner = fixture.fetch(:owner)
_, evidence = Object.new.extend(BirthdayProductionFixture).seed_birthday_review(owner)
credits = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/discovery/blur-checked-editions.json").read).first.fetch("artist-credit")

# Use a separate, title-only observation to exercise ambiguity without
# resolving one of the exact source recording IDs by default.
ambiguous_candidates = %w[
  f2903d45-03c8-4631-a1e1-3d0d33c57cbe
  6eb416f2-5649-497a-b36e-2e47c92f366b
  35b0f752-a764-46dd-a596-a9fb84b1ac96
]
recordings = JSON.parse(Rails.root.join("docs/design/unified-resolution/musicbrainz-recordings.json").read)
candidates = recordings.select { |recording| ambiguous_candidates.include?(recording.fetch("id")) }
  .map { |recording| recording.slice("id", "title", "length", "disambiguation").merge("artist-credit" => credits) }
ambiguous = Scrobble.create!(id: 293200, user: owner, lastfm_account: owner.source_account, played_at: Time.utc(2026, 11, 25),
  payload: { "artist_name" => "Blur", "track_name" => "There's No Other Way", "album_name" => "Leisure" })
ambiguous_surface = RecordingResolution::Ledger.attach!(ambiguous)
ambiguous_claims = ambiguous.payload.slice(*RecordingResolution::PilotRunner::CLAIM_FIELDS)
ambiguous_group = RecordingResolution::Group.create!(surface_id: ambiguous_surface.id, version: RecordingResolution::Ledger::VERSION,
  claims: ambiguous_claims)
ambiguity = evidence.slice("construction_editions", "review_tracklists", "reviewed_adjacent_programs", "reassessment")
  .merge("candidates" => candidates, "source_claims" => ambiguous_claims)
RecordingResolution::Assessment.create!(group_id: ambiguous_group.id, version: RecordingResolution::Assessment::INTERPRETATION_VERSION,
  digest: Digest::SHA256.hexdigest(ambiguity.to_json), actor: "fixture", evidence: ambiguity)


require Rails.root.join("spec/support/discovery_replay")
require Rails.root.join("spec/support/release_membership_fixture")
membership_fixture = Object.new.extend(ReleaseMembershipFixture)
ReleaseMembershipFixture::CASES.each do |entry|
  plays, previous, _, _, provider = membership_fixture.seed_release_membership_case(owner, entry)
  request = RecordingResolution::Investigation.new(owner, plays.first).request(refresh: true, reassessment: previous)
  CanonicalCatalog::Processor.new(request, session_factory: ->(*) { provider }).call
  abort "Expected completed membership investigation" unless request.reload.state == "imported"
end
