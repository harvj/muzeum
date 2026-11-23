module RecordingResolution
  class EditionDiscovery
    MAX_LOOKUPS = 2
    MAX_SLOTS = 100
    MAX_ORIGINAL_LOOKUPS = 25

    attr_reader :tracklists, :construction_editions, :pending_original_group

    def initialize(musicbrainz, session, artist_mbid: nil)
      @musicbrainz = musicbrainz
      @session = session
      @artist_mbid = artist_mbid
    end

    def call(surface, candidates, checked:, attempted:, search:, review_alternative: false, preferred: nil)
      @pending_original_group = nil
      @tracklists = {}
      @construction_editions = {}
      results = [ checked ].compact
      if surface.album.present? && search
        results.concat(related_editions(surface, candidates, attempted || checked&.fetch("id", nil)))
      end
      results.each { |edition| retain(edition.fetch("id"), edition) }
      retain(attempted, nil) if attempted && checked.nil? && release_request(attempted)
      found = results.flat_map { |edition| appearances(surface, edition) }
      # Preserve a fixed fallback budget even when search supplies many releases.
      unless preferred || review_alternative || results.empty?
        retain_original_editions
        return found
      end

      references = candidates.filter_map do |candidate|
        next if found.any? { |row| row["id"] == candidate["id"] }

        Array(candidate["releases"]).find { |release| Clients::Musicbrainz::MBID.match?(release["id"].to_s) }&.fetch("id")
      end
      [ preferred, *references ].compact.uniq.reject { |id| @tracklists.key?(id) || id == attempted }
        .first(1).each do |id|
        tracklist = nil
        local = Release.find_by(ingested_from_release_mbid: id)
        tracklist = ReviewRelease.from_local(local) if local
        if tracklist
          @tracklists[id] = tracklist
        else
          edition = lookup(id)
          found.concat(appearances(surface, edition)) if edition
        end
      end
      retain_original_editions
      found
    end

    private

    def retain_original_editions
      context = @construction_editions.values.first
      return unless context

      group = context.fetch("release-group")
      title = group["title"].presence || DiscoveryTitle.album_base(context["title"])
      references = @musicbrainz.collection_editions(@session, group.fetch("id"), limit: MAX_ORIGINAL_LOOKUPS).select do |row|
        row["status"] == "Official" && row["date"] == group["first-release-date"] &&
          DiscoveryTitle.match?(DiscoveryTitle.album_base(row["title"]), title)
      end
      references = references.reject { |row| @construction_editions.key?(row["id"]) }
      originals = references.map do |row|
        id = row.fetch("id")
        edition = @musicbrainz.edition(@session, id, catalog: true)
        unless edition && edition.dig("release-group", "id") == group["id"] &&
            CanonicalCatalog::Edition.original_context?(edition)
          raise CanonicalCatalog::Store::Unverified, "Original edition could not be verified"
        end
        CanonicalCatalog::Edition.new(edition, id)
      end
      originals.each { |edition| retain(edition.data.fetch("id"), edition.data) }
    rescue ProviderError => error
      raise if error.deferred

      @pending_original_group = group["id"]
    rescue CanonicalCatalog::Store::Unverified
      @pending_original_group = group["id"]
    end

    def retain(id, edition)
      if edition && CanonicalCatalog::Edition.collection_context?(edition) &&
          Array(edition["media"]).sum { |medium| Array(medium["tracks"]).size } <= MAX_SLOTS
        @construction_editions[id] = edition
      end
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
        search = @musicbrainz.release_candidates(@session, artist: surface.artist, title: DiscoveryTitle.album_base(surface.album), artist_mbid: @artist_mbid)
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
      return credits.any? { |credit| credit.dig("artist", "id") == @artist_mbid } if @artist_mbid

      names = credits.flat_map { |credit| [ credit["name"], credit.dig("artist", "name") ] }
      names << credits.map { |credit| "#{credit['name']}#{credit['joinphrase']}" }.join

      names.any? { |name| DiscoveryTitle.match?(name, surface.artist) }
    end
  end
end
