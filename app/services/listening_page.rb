class ListeningPage
  SIZE = 50

  def self.fetch(observations, before:)
    plays = chronological(observations, before:).limit(SIZE + 1).select(:id, :lastfm_account_id, :played_at, :payload).to_a
    if plays.size > SIZE
      plays.pop
      next_page = plays.last.id
    end
    [ plays, next_page ]
  end

  def self.chronological(observations, before:)
    if before.present?
      raise ActiveRecord::RecordNotFound unless before.is_a?(String) || before.is_a?(Integer)

      cursor = observations.reselect(:id, :played_at).find(before)
      observations = observations.where("(scrobbles.played_at, scrobbles.id) < (?, ?)", cursor.played_at, cursor.id)
    end
    observations.reorder(played_at: :desc, id: :desc)
  end

  def self.catalog(plays, effective)
    return [ {}, {} ] if plays.empty?

    rows = plays.map do |play|
      { id: play.id, lastfm_account_id: play.lastfm_account_id,
        payload: play.payload.slice(*RecordingResolution::Ledger::PAYLOAD_FIELDS) }
    end
    # Resolve only the records read by the authorized page query. The ledger still checks its grant.
    page_source = Arel.sql(
      "jsonb_to_recordset(?::jsonb) AS scrobbles(id bigint, lastfm_account_id bigint, payload jsonb)", rows.to_json
    )
    effective_ids = effective.from(page_source)
      .where.not("effective_resolution.recording_id" => nil)
      .pluck("scrobbles.id", Arel.sql("effective_resolution.recording_id")).to_h
    recordings = Recording.where(id: effective_ids.values).eager_load(recording_artists: :artist).index_by(&:id)

    releases = Release.joins(:catalog_track_slots)
      .where(catalog_track_slots: { recording_id: recordings.keys }).where.not(catalog_verified_at: nil)
      .select("releases.*", "catalog_track_slots.recording_id AS member_recording_id").distinct.order(:title, :id)
      .group_by(&:member_recording_id)
    recent_releases = effective_ids.transform_values { |recording_id| releases.fetch(recording_id, []) }
    [ effective_ids.transform_values { |id| recordings[id] }, recent_releases ]
  end
end
