class ListeningPage
  SIZE = 50

  def self.chronological(observations, before:)
    if before.present?
      cursor = observations.reselect(:id, :played_at).find(before)
      observations = observations.where("(scrobbles.played_at, scrobbles.id) < (?, ?)", cursor.played_at, cursor.id)
    end
    observations.reorder(played_at: :desc, id: :desc)
  end

  def self.catalog(plays, effective)
    effective_ids = effective.where(scrobbles: { id: plays.map(&:id) })
      .where.not("effective_resolution.recording_id" => nil)
      .pluck("scrobbles.id", Arel.sql("effective_resolution.recording_id")).to_h
    recordings = Recording.where(id: effective_ids.values).eager_load(recording_artists: :artist).index_by(&:id)

    releases = Release.joins(:catalog_track_slots)
      .where(catalog_track_slots: { recording_id: recordings.keys }, title: plays.filter_map { |play| play.payload["album_name"].presence })
      .where.not(catalog_verified_at: nil)
      .select("releases.*", "catalog_track_slots.recording_id AS member_recording_id").distinct
      .group_by(&:member_recording_id)
    recent_releases = plays.each_with_object({}) do |play, matches|
      candidates = releases.fetch(effective_ids[play.id], []).select { |release| release.title == play.payload["album_name"] }
      if (edition = play.payload["album_mbid"].presence)
        candidates.select! { |release| release.ingested_from_release_mbid == edition }
      end
      matches[play.id] = candidates.first if candidates.one?
    end
    [ effective_ids.transform_values { |id| recordings[id] }, recent_releases ]
  end
end
