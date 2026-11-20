module RecordingResolution
  class LocalCandidates
    LIMIT = 25

    def self.call(surface, claims)
      title = surface.track.to_s.downcase
      id = claims["track_mbid"].to_s.downcase
      rows = Recording.where("lower(title) = ?", title).or(Recording.where(mbid: id))
        .order(Arel.sql(Recording.sanitize_sql_array([ "CASE WHEN mbid = ? THEN 0 ELSE 1 END", id ])), :id)
        .limit(LIMIT).includes(:artists).to_a
      verified_id = rows.find { |recording| recording.mbid == id }&.id
      verified = verified_id && CatalogRevision.exists?(entity_type: "Recording", entity_id: verified_id)
      rows.map do |recording|
        {
          "id" => recording.mbid, "title" => recording.title, "length" => recording.duration_ms,
          "resolution_candidate_source" => "local_catalog",
          "verified_local_claim" => verified && recording.id == verified_id,
          "artist-credit" => recording.artists.map { |artist|
            { "name" => artist.name, "artist" => { "id" => artist.mbid, "name" => artist.name } }
          }
        }
      end
    end
  end
end
