module RecordingResolution
  class LocalCandidates
    LIMIT = 25

    def self.call(surface, claims)
      title = DiscoveryTitle.key(surface.track)
      titles = [ surface.track.to_s.downcase, title, title.tr("'", "’") ].uniq
      id = claims["track_mbid"].to_s.downcase
      rows = Recording.where("lower(title) IN (?)", titles).or(Recording.where(mbid: id))
        .order(Arel.sql(Recording.sanitize_sql_array([ "CASE WHEN mbid = ? THEN 0 ELSE 1 END", id ])), :id)
        .limit(LIMIT).includes(:artists).to_a
      verified_id = rows.find { |recording| recording.mbid == id }&.id
      verified = verified_id && CatalogRevision.exists?(entity_type: "Recording", entity_id: verified_id)
      direct = rows.map do |recording|
        {
          "id" => recording.mbid, "title" => recording.title, "length" => recording.duration_ms,
          "resolution_candidate_source" => "local_catalog",
          "verified_local_claim" => verified && recording.id == verified_id,
          "artist-credit" => recording.artists.map { |artist|
            { "name" => artist.name, "artist" => { "id" => artist.mbid, "name" => artist.name } }
          }
        }
      end
      context = release_candidates(surface, claims, rows.map(&:id)).index_by { |candidate| candidate["id"] }
      direct = direct.map { |candidate| candidate.merge(context.delete(candidate["id"]) || {}) }
      (direct + context.values).first(LIMIT)
    end

    def self.release_candidates(surface, claims, recording_ids)
      return [] if surface.album.blank? && claims["album_mbid"].blank?

      editions = Release.where.not(catalog_verified_at: nil)
      editions = if claims["album_mbid"].present?
        editions.where(ingested_from_release_mbid: claims["album_mbid"].to_s.downcase)
      else
        editions.where(title: [ surface.album, DiscoveryTitle.album_base(surface.album) ].uniq,
          id: CatalogTrackSlot.where(recording_id: recording_ids).select(:release_id))
      end
      editions.order(:id).limit(4).flat_map do |release|
        tracklist = ReleaseTracklist.new(release)
        matching = tracklist.slots.select do |slot|
          [ slot.title, slot.recording.title ].any? { |title| DiscoveryTitle.match?(title, surface.track) }
        end
        matching.map do |slot|
          candidate = ReleaseTracklist.candidate(slot.recording, tracklist.evidence)
          candidate["verified_local_claim"] = slot.recording.mbid.casecmp?(claims["track_mbid"].to_s)
          candidate
        end
      rescue ArgumentError
        []
      end
    end
    private_class_method :release_candidates

    def self.checked_edition(claims, candidates)
      claimed = claims["album_mbid"].to_s
      return {} unless Clients::Musicbrainz::MBID.match?(claimed)

      context = candidates.pluck("local_release_context").compact.find do |row|
        row.fetch("edition_mbid").casecmp?(claimed)
      end
      return {} unless context && (release = Release.find_by(id: context.fetch("release_id")))

      tracklist = ReleaseTracklist.new(release)
      tracklist.evidence == context ? tracklist.assessment_fields : {}
    rescue ArgumentError
      {}
    end
  end
end
