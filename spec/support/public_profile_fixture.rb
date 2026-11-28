module PublicProfileFixture
  def listening_profile_fixture
    owner = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "fixture-profile-owner", lastfm_username: "qalephd")
    account = owner.source_account
    profile = ListeningProfile.establish!(account:, owner:, reference: "Disposable administrative fixture")
    artist = Artist.create!(name: "North Shore Ensemble", mbid: SecureRandom.uuid)
    album = Release.create!(title: "Harbor Sessions", release_year: 2008, catalog_verified_at: Time.current, ingested_from_release_mbid: SecureRandom.uuid)
    album.artists << artist
    import = CatalogImport.create!(kind: "release_construction", entity_id: album.id, state: "imported", due_at: Time.current)
    CatalogRevision.create!(catalog_import: import, entity_type: "Release", entity_id: album.id,
      evidence: { "edition_mbid" => album.ingested_from_release_mbid, "original_context" => true })
    recording = Recording.create!(title: "Harbor Lights", mbid: SecureRandom.uuid, duration_ms: 240_000)
    recording.artists << artist
    unplayed = Recording.create!(title: "The Empty Pier", mbid: SecureRandom.uuid)
    unplayed.artists << artist
    [ recording, unplayed ].each.with_index(1) do |track, position|
      album.catalog_track_slots.create!(recording: track, medium: 1, position:, title: track.title, track_mbid: SecureRandom.uuid)
    end
    resolved = owner.scrobbles.create!(played_at: Time.utc(2024, 5, 3, 17),
      payload: { artist_name: artist.name, album_name: album.title, track_name: "Harbor Lights (reported)", private_marker: "unpublished source detail" })
    unresolved = owner.scrobbles.create!(played_at: Time.utc(2024, 5, 3, 16),
      payload: { artist_name: artist.name, album_name: "Unknown", track_name: "An unrecognized track" })
    RecordingResolution::Ledger.record!(listener: owner, scrobble: resolved, scope: :scrobble,
      mode: "resolved", reason: "Private fixture rationale", recording:)
    { profile:, owner:, account:, artist:, album:, recording:, unplayed:, resolved:, unresolved: }
  end

  def authorize_fixture_publication(fixture)
    profile = fixture.fetch(:profile)
    profile.record_consent!(consenting_owner: fixture.fetch(:owner), reference: "disposable-consent-fixture")
    profile.activate_publication!(provider_reference: "disposable-policy-fixture")
  end
end
