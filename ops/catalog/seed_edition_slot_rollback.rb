abort "Expected disposable test database" unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database.match?(/\Amuzeum_edition_rollback(?:_\d+)?_test\z/)
require Rails.root.join("spec/support/guilt_show_fixture")
fixture = Object.new.extend(GuiltShowFixture)
user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "rollback-check", lastfm_username: "rollback-check")
plays, assessment, data, = fixture.guilt_show_assessment(user)
recording = CanonicalCatalog::Store.recording!(data)
proposal = CanonicalCatalog::ReviewedConstruction.for(assessment, recording.mbid).sole
request = CatalogImport.create!(kind: "release_construction", entity_id: recording.id, due_at: Time.current,
  state: "imported", context: { "assessment_id" => assessment.id, "reviewer_id" => user.id })
release = Release.create!(title: "Guilt Show", release_group_mbid: proposal.construction.base.data.dig("release-group", "id"),
  ingested_from_release_mbid: proposal.construction.appearances.last.fetch("id"), release_year: 2004, release_month: 8, release_day: 21)
release = CanonicalCatalog::ReviewedConstruction.apply!(proposal, request, assessment, corrected_release: release)
RecordingResolution::Ledger.record!(listener: user, scrobble: plays.first, scope: :surface, mode: "resolved",
  reason: "Rollback fixture", recording:, assessment:)
CanonicalCatalog::RecordingChronology.record!(recording, user, start_date: "2003", end_date: "2004-01", source: "Disposable session notes")
MusicalIdentityDecision.create!(entity: recording, user:, colors: %w[gray])
MusicalIdentityDecision.create!(entity: recording, user:, colors: %w[salmon gray], rationale: "Disposable correction")
bonus = release.catalog_track_slots.additional_appearances.sole
bonus.dup.tap { |row| row.edition_mbid = SecureRandom.uuid }.save!
other_release = Release.create!(title: "Disposable overlapping release", catalog_verified_at: Time.current)
other_release.catalog_track_slots.create!(recording:, medium: 1, position: 1, title: recording.title, track_mbid: SecureRandom.uuid)
puts [ release.id, recording.id, user.id, other_release.id ].join(",")
