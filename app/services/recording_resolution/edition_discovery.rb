module RecordingResolution
  class EditionDiscovery
    MAX_LOOKUPS = 2
    MAX_SLOTS = 100

    attr_reader :tracklists

    def initialize(musicbrainz, session)
      @musicbrainz = musicbrainz
      @session = session
    end

    def call(surface, claims, candidates, checked:, attempted:, search:, review_alternative: false, preferred: nil)
      @tracklists = {}
      results = [ checked ].compact
      if surface.album.present? && search
        results.concat(related_editions(surface, candidates, attempted || checked&.fetch("id", nil)))
      end
      results.each { |edition| retain(edition.fetch("id"), edition) }
      retain(attempted, nil) if attempted && checked.nil? && release_request(attempted)
      found = results.flat_map { |edition| appearances(surface, edition) }
      # Preserve a fixed fallback budget even when search supplies many releases.
      return found unless preferred || review_alternative || results.empty?

      references = candidates.filter_map do |candidate|
        next if found.any? { |row| row["id"] == candidate["id"] }

        Array(candidate["releases"]).find { |release| Clients::Musicbrainz::MBID.match?(release["id"].to_s) }&.fetch("id")
      end
      album_hint = claims["album_mbid"].to_s.downcase
      album_hint = nil unless Clients::Musicbrainz::MBID.match?(album_hint)
      [ preferred, *references, album_hint ].compact.uniq.reject { |id| @tracklists.key?(id) || id == attempted }
        .first(1).each do |id|
        tracklist = nil
        local = Release.find_by(ingested_from_release_mbid: id)
        tracklist = ReviewRelease.from_local(local) if local
        if tracklist
          @tracklists[id] = tracklist
        else
          edition = lookup(id)
          found.concat(appearances(surface, edition)) if edition && id == album_hint
        end
      end
      found
    end

    private

    def retain(id, edition)
      request = release_request(id)
      @tracklists[id] = (edition ? ReviewRelease.project(edition) : { "state" => "missing" }).merge(
        "provider" => "musicbrainz", "retrieved_at" => request&.fetch("retrieved_at", nil))
    end

    def release_request(id)
      @session.provenance.reverse.find { |entry| entry["endpoint"] == "/ws/2/release/#{id}" }
    end

    def lookup(id)
      edition = @musicbrainz.edition(@session, id, catalog: true)
      edition = nil unless edition&.fetch("id", nil) == id
      retain(id, edition)
      edition
    rescue ProviderError => error
      raise if error.deferred

      @tracklists[id] = { "state" => "unavailable", "provider" => "musicbrainz", "http_status" => error.http_status }.compact
      nil
    end

    def related_editions(surface, candidates, attempted)
      references = candidates.flat_map { |candidate| Array(candidate["releases"]) }
      refs = references.uniq { |row| row["id"] }.select { |row| DiscoveryTitle.release_context?(surface.album, row) }
      unless refs.any? { |ref| DiscoveryTitle.displayed_edition?(surface.album, ref) }
        search = @musicbrainz.release_candidates(@session, artist: surface.artist, title: DiscoveryTitle.album_base(surface.album))
          .select { |row| DiscoveryTitle.release_context?(surface.album, row) }
        refs = (search + refs).uniq { |row| row["id"] }
      end
      refs = refs.reject { |row| row["id"] == attempted } if attempted
      remaining = attempted ? MAX_LOOKUPS - 1 : MAX_LOOKUPS
      refs.sort_by { |row| [ DiscoveryTitle.displayed_edition?(surface.album, row) ? 0 : 1, row["id"].to_s ] }
        .filter_map { |row| row["id"] if Clients::Musicbrainz::MBID.match?(row["id"].to_s) }.uniq.first(remaining).filter_map do |id|
        edition = @musicbrainz.edition(@session, id, catalog: true)
        edition if edition && edition["id"] == id && DiscoveryTitle.release_context?(surface.album, edition)
      end
    end

    def appearances(surface, edition)
      id = edition["id"]
      return [] unless Clients::Musicbrainz::MBID.match?(id.to_s)
      return [] unless DiscoveryTitle.release_context?(surface.album, edition)

      media = Array(edition["media"])
      return [] unless media.sum { |medium| Array(medium["tracks"]).size } <= MAX_SLOTS

      media.flat_map do |medium|
        tracks = medium["tracks"]
        # Incomplete media cannot add recordings based on a fragment.
        next [] unless tracks.is_a?(Array) && tracks.size == medium["track-count"]

        tracks.filter_map do |slot|
          recording = slot["recording"]
          next unless recording && Clients::Musicbrainz::MBID.match?(recording["id"].to_s) &&
            DiscoveryTitle.match?(slot["title"], surface.track) && artist_matches?(surface, recording)

          appearance = edition.slice("id", "title", "disambiguation", "date", "country", "release-group").merge(
            "relationship" => (DiscoveryTitle.displayed_edition?(surface.album, edition) ? "matching_catalog_caption" : "related_catalog_title"),
            "medium" => medium["position"], "position" => slot["position"], "track_mbid" => slot["id"],
            "track_title" => slot["title"])
          recording.merge("release_discovery" => appearance, "releases" => [ edition.slice("id", "title", "date", "country") ])
        end
      end
    end

    def artist_matches?(surface, recording)
      credits = Array(recording["artist-credit"])
      names = credits.flat_map { |credit| [ credit["name"], credit.dig("artist", "name") ] }
      names << credits.map { |credit| "#{credit['name']}#{credit['joinphrase']}" }.join

      names.any? { |name| DiscoveryTitle.match?(name, surface.artist) }
    end
  end
end
