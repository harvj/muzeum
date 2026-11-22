module RecordingResolution
  class LocalCandidates
    LIMIT = 25

    def self.call(surface, claims)
      title = DiscoveryTitle.key(surface.track)
      titles = [ surface.track.to_s.downcase, title, title.tr("'", "’") ].uniq
      id = claims["track_mbid"].to_s.downcase
      rows = Recording.where("lower(title) IN (?)", titles).order(:id).limit(LIMIT).includes(:artists).to_a
      if Clients::Musicbrainz::MBID.match?(id) && rows.none? { |recording| recording.mbid == id }
        hint = Recording.includes(:artists).find_by(mbid: id)
      end
      direct = rows.map do |recording|
        {
          "id" => recording.mbid, "title" => recording.title, "length" => recording.duration_ms,
          "resolution_candidate_source" => "local_catalog",
          "artist-credit" => recording.artists.map { |artist|
            { "name" => artist.name, "artist" => { "id" => artist.mbid, "name" => artist.name } }
          }
        }
      end
      context = release_candidates(surface, claims, rows.map(&:id)).index_by { |candidate| candidate["id"] }
      direct = direct.map { |candidate| candidate.merge(context.delete(candidate["id"]) || {}) }
      candidates = (direct + context.values).first(LIMIT)
      if hint && candidates.none? { |candidate| candidate["id"] == id }
        candidates << ReleaseTracklist.candidate(hint, {}).except("local_release_context")
      end
      candidates
    end

    def self.release_candidates(surface, claims, recording_ids)
      return [] if surface.album.blank? && claims["album_mbid"].blank?

      editions = Release.where.not(catalog_verified_at: nil)
      independent = editions.where(title: [ surface.album, DiscoveryTitle.album_base(surface.album) ].uniq,
        id: CatalogTrackSlot.where(recording_id: recording_ids).select(:release_id))
      editions = independent.order(:id).limit(4).to_a
      hint = Release.where.not(catalog_verified_at: nil).find_by(ingested_from_release_mbid: claims["album_mbid"].to_s.downcase) if claims["album_mbid"].present?
      editions |= [ hint ] if hint
      editions.flat_map do |release|
        tracklist = ReleaseTracklist.new(release)
        matching = tracklist.slots.select do |slot|
          [ slot.title, slot.recording.title ].any? { |title| DiscoveryTitle.match?(title, surface.track) }
        end
        matching.map do |slot|
          ReleaseTracklist.candidate(slot.recording, tracklist.evidence)
        end
      rescue ArgumentError
        []
      end
    end
    private_class_method :release_candidates

    def self.checked_edition(surface, candidates)
      contexts = candidates.pluck("local_release_context").compact.uniq
      return {} unless contexts.one? && (release = Release.find_by(id: contexts.first.fetch("release_id")))
      return {} unless release.title == surface.album

      tracklist = ReleaseTracklist.new(release)
      tracklist.evidence == contexts.first ? tracklist.assessment_fields : {}
    rescue ArgumentError
      {}
    end
  end
end
