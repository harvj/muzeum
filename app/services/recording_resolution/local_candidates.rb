module RecordingResolution
  class LocalCandidates
    LIMIT = 25

    def self.call(surface)
      title = DiscoveryTitle.key(surface.track)
      interpretation = TitleInterpretation.call(surface.track)
      base = interpretation["base_title"] if TitleInterpretation.mastering_only?(interpretation)
      titles = [ surface.track.to_s.downcase, title, DiscoveryTitle.key(base) ].reject(&:blank?)
      titles = titles.flat_map { |value| [ value, value.tr("'", "’") ] }.uniq
      rows = Recording.where("lower(title) IN (?)", titles).order(:id).limit(LIMIT).includes(:artists).to_a
      direct = rows.map do |recording|
        {
          "id" => recording.mbid, "title" => recording.title, "length" => recording.duration_ms,
          "resolution_candidate_source" => "local_catalog",
          "artist-credit" => recording.artists.map { |artist|
            { "name" => artist.name, "artist" => { "id" => artist.mbid, "name" => artist.name } }
          }
        }
      end
      context = release_candidates(surface, rows.map(&:id)).uniq { |candidate| candidate["id"] }.index_by { |candidate| candidate["id"] }
      direct = direct.map { |candidate| candidate.merge(context.delete(candidate["id"]) || {}) }
      (direct + context.values).first(LIMIT)
    end

    def self.release_candidates(surface, recording_ids)
      return [] if surface.album.blank?

      Release.where.not(catalog_verified_at: nil)
        .where(title: [ surface.album, DiscoveryTitle.album_base(surface.album) ].uniq,
          id: CatalogTrackSlot.where(recording_id: recording_ids).select(:release_id))
        .order(:id).limit(4).flat_map do |release|
        tracklist = ReleaseTracklist.new(release)
        matching = tracklist.slots.select do |slot|
          [ slot.title, slot.recording.title ].any? { |title| DiscoveryTitle.match?(title, surface.track) || mastering_title_match?(surface.track, title) }
        end
        matching.map do |slot|
          ReleaseTracklist.candidate(slot.recording, tracklist.evidence)
        end
      rescue ArgumentError
        []
      end
    end
    def self.mastering_title_match?(observed, title)
      interpretation = TitleInterpretation.call(observed)
      TitleInterpretation.mastering_only?(interpretation) && DiscoveryTitle.match?(interpretation["base_title"], title)
    end
    private_class_method :release_candidates, :mastering_title_match?

    def self.catalog_identity(surface)
      artist = stored_artist(surface.artist)
      return {} unless artist && Clients::Musicbrainz::MBID.match?(artist.mbid.to_s)

      editions = Release.where(id: artist.release_artists.select(:release_id), title: surface.album, catalog_verified_at: ..Time.current)
        .where.not(ingested_from_release_mbid: nil).limit(2).to_a
      identity = { artist_mbid: artist.mbid }
      recordings = artist.recordings.where("lower(recordings.title) = ?", surface.track.to_s.downcase).limit(2).to_a
      if recordings.one? && Clients::Musicbrainz::MBID.match?(recordings.first.mbid.to_s) &&
          CatalogRevision.exists?(entity_type: "Recording", entity_id: recordings.first.id)
        identity[:recording_mbid] = recordings.first.mbid
      end
      if editions.one? && Clients::Musicbrainz::MBID.match?(editions.first.ingested_from_release_mbid.to_s)
        identity[:edition_mbid] = editions.first.ingested_from_release_mbid
      end
      identity
    end

    def self.stored_artist(name)
      artists = Artist.where("lower(name) = ?", name.to_s.downcase).limit(2).to_a
      return artists.first if artists.one?
      return if artists.any? || name.blank?

      # Only aliases retained from verified provider credits are eligible for reuse.
      rows = CatalogRevision.where(entity_type: "Recording")
        .where("evidence @> ?", { artist_credit: [ { credited_name: name } ] }.to_json)
        .joins("CROSS JOIN LATERAL jsonb_array_elements(catalog_revisions.evidence->'artist_credit') AS credit")
        .where("credit->>'credited_name' = ?", name)
        .distinct.limit(2).pluck(Arel.sql("credit->>'artist_mbid'"))
      Artist.find_by(mbid: rows.first) if rows.one?
    end
    private_class_method :stored_artist

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
