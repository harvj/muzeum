class PublicProfileCatalog
  def initialize(profile)
    @profile = profile
  end

  def observations
    Scrobble.where(lastfm_account_id: @profile.lastfm_account_id)
  end

  def effective
    RecordingResolution::Ledger.effective(@profile.owner).where(lastfm_account_id: @profile.lastfm_account_id)
  end

  def catalog_plays
    return effective.none if candidate_keys.empty?

    effective.where("#{RecordingResolution::Ledger::EXACT_KEY_SQL} IN (?)", candidate_keys)
      .where.not("effective_resolution.recording_id" => nil)
  end

  def releases
    Release.where.not(catalog_verified_at: nil).where(id: CatalogTrackSlot.where(recording_id: played_recording_ids).select(:release_id))
  end

  def recordings
    slots = CatalogTrackSlot.where(release_id: releases.select(:id)).select(:recording_id)
    Recording.where(id: played_recording_ids).or(Recording.where(id: slots))
  end

  def artists
    Artist.where(id: RecordingArtist.where(recording_id: recordings.select(:id)).select(:artist_id))
      .or(Artist.where(id: ReleaseArtist.where(release_id: releases.select(:id)).select(:artist_id)))
  end

  private

  def played_recording_ids
    @played_recording_ids ||= catalog_plays.distinct.pluck(Arel.sql("effective_resolution.recording_id"))
  end

  def candidate_keys
    @candidate_keys ||= begin
      candidates = RecordingResolution::Decision.where(user_id: [ nil, @profile.owner_id ], mode: "resolved").select(:surface_id)
      RecordingResolution::Surface.where(lastfm_account_id: @profile.lastfm_account_id, id: candidates).pluck(:exact_key)
    end
  end
end
