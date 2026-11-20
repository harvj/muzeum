module RecordingResolution
  class EditionDiscovery
    MAX_LOOKUPS = 2
    MAX_SLOTS = 100

    def initialize(musicbrainz, session)
      @musicbrainz = musicbrainz
      @session = session
    end

    def call(surface, claims, candidates, checked:, attempted:, search:)
      results = [ checked ].compact
      # An explicit source edition has already had its one lookup, even when unavailable.
      if checked.nil? && claims["album_mbid"].blank? && surface.album.present? && search
        results.concat(related_editions(surface, candidates, attempted))
      end
      results.flat_map { |edition| appearances(surface, claims, edition) }
    end

    private

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

    def appearances(surface, claims, edition)
      id = edition["id"]
      return [] unless Clients::Musicbrainz::MBID.match?(id.to_s)
      return [] if claims["album_mbid"].present? && !id.casecmp?(claims["album_mbid"])
      return [] unless DiscoveryTitle.release_context?(surface.album, edition) || claims["album_mbid"].present?

      media = Array(edition["media"])
      return [] unless media.sum { |medium| Array(medium["tracks"]).size } <= MAX_SLOTS

      media.flat_map do |medium|
        tracks = medium["tracks"]
        # Incomplete media cannot add recordings based on a fragment.
        next [] unless tracks.is_a?(Array) && tracks.size == medium["track-count"]

        tracks.filter_map do |slot|
          recording = slot["recording"]
          next unless recording && Clients::Musicbrainz::MBID.match?(recording["id"].to_s) &&
            DiscoveryTitle.match?(slot["title"], surface.track) && artist_matches?(surface, claims, recording)

          appearance = edition.slice("id", "title", "disambiguation", "date", "country", "release-group").merge(
            "relationship" => (DiscoveryTitle.displayed_edition?(surface.album, edition) ? "matching_catalog_caption" : "related_catalog_title"),
            "medium" => medium["position"], "position" => slot["position"], "track_mbid" => slot["id"],
            "track_title" => slot["title"])
          recording.merge("release_discovery" => appearance, "releases" => [ edition.slice("id", "title", "date", "country") ])
        end
      end
    end

    def artist_matches?(surface, claims, recording)
      credits = Array(recording["artist-credit"])
      ids = credits.filter_map { |credit| credit.dig("artist", "id") }
      names = credits.flat_map { |credit| [ credit["name"], credit.dig("artist", "name") ] }
      names << credits.map { |credit| "#{credit['name']}#{credit['joinphrase']}" }.join
      artist_claim = claims["artist_mbid"]
      return false if Clients::Musicbrainz::MBID.match?(artist_claim.to_s) && ids.any? && ids.none? { |id| id.casecmp?(artist_claim) }

      names.any? { |name| DiscoveryTitle.match?(name, surface.artist) }
    end
  end
end
