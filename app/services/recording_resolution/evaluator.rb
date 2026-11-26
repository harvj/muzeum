module RecordingResolution
  class Evaluator
    VERSION = "recording-evidence-v2"
    VERSION_MARKER = /\b(live|remix|remixed|acoustic|demo|alternate|edit|instrumental|take)\b/i

    attr_reader :evidence

    def initialize(session, discogs:, workspace: false, discover: workspace, review_alternative: false, review_release: nil, catalog_identity: {}, origins: true, adaptive: false)
      @session = session
      @discogs = DiscogsEvidence.new(discogs, expanded: workspace) if discogs
      @workspace = workspace
      @discover = discover
      @review_alternative = review_alternative
      @review_release = review_release
      @catalog_identity = catalog_identity
      @origins = origins
      @adaptive = adaptive
      @musicbrainz = Clients::Musicbrainz.new
    end

    def call(surface, claims)
      @evidence = { "source_claims" => claims, "reasons" => [], "reason_details" => {} }
      if surface.track.blank? || surface.artist.blank?
        reason("missing_title_or_artist", "missing_fields" => %w[artist track].select { |field| surface.public_send(field).blank? })
        return evidence
      end

      evidence["canonical_artist_mbid"] = @catalog_identity[:artist_mbid] if @catalog_identity[:artist_mbid]
      evidence["title_interpretation"] = TitleInterpretation.call(surface.track) if @workspace
      page = recording_page(surface)
      candidates = page.fetch("recordings")
      evidence["search"] = page.slice("count", "offset").merge("returned" => candidates.size) unless evidence["recording_searches"]
      evidence["candidates"] = candidates.map { |candidate| recording_evidence(candidate) }
      yield evidence if block_given?
      reason("incomplete_search", { "provider" => "musicbrainz" }.merge(evidence["search"] || {})) if page["incomplete"] || page["count"] != candidates.size
      reason("missing_album", "field" => "album") if surface.album.blank?
      reason("missing_source_mbid", "field" => "track_mbid") if claims["track_mbid"].blank?

      verification = if !@workspace && claims["track_mbid"].present?
        @musicbrainz.verify_recording(@session, claims["track_mbid"])
      else
        {}
      end
      recording = verification["data"]
      evidence["verification"] = verification.except("data")
      evidence["verified_recording"] = recording && recording_evidence(recording)
      verified = verified_recording?(recording, verification["redirected_to"] || claims["track_mbid"])
      if verified
        assess_identity(surface, claims, recording, candidates)
      elsif !@workspace
        reason("unverified_recording", evidence["verification"].merge("claimed_mbid" => claims["track_mbid"],
          "returned_mbid" => recording&.fetch("id", nil)))
      end

      releases = Array(recording&.fetch("releases", nil))
      edition_id = (claims["album_mbid"].presence || releases.find { |release| release["title"] == surface.album }&.fetch("id", nil)) unless @workspace
      edition_id ||= @catalog_identity[:edition_mbid] if @workspace
      if @workspace && edition_id.blank? && surface.album.present?
        relevant = candidates.flat_map { |candidate| Array(candidate["releases"]) }.select { |release| release["title"] == surface.album }
        ids = relevant.pluck("id").compact.uniq
        edition_id = ids.first if ids.one?
      end
      if edition_id && surface.album.present?
        edition = @musicbrainz.edition(@session, edition_id, catalog: @workspace)
      end
      if edition
        evidence["edition"] = edition.slice("id", "title", "release-group", "country", "date").merge(
          "countries" => Array(edition["release-events"]).flat_map { |event| Array(event["country_codes"]) }.uniq,
          "formats" => Array(edition["media"]).filter_map { |medium| medium["format"].presence }.uniq,
          "complete_tracklist" => complete_edition?(edition) && Array(edition["media"]).none? { |medium| medium["extra-track-layout"] })
      end
      evidence["slots"] = edition_slots(edition)
      if @discover
        related = !edition || evidence["slots"].none? { |slot| DiscoveryTitle.match?(slot["title"], surface.track) } ||
          DiscoveryTitle.album_base(surface.album) != surface.album || surface.album.to_s.match?(VERSION_MARKER)
        search = related
        discovery = EditionDiscovery.new(@musicbrainz, @session, **@catalog_identity.slice(:artist_mbid))
        merge_discovered(discovery.call(surface, candidates, checked: edition, attempted: edition_id, search:, review_alternative: @review_alternative, preferred: @review_release, origins: @origins))
        evidence["review_tracklists"] = discovery.tracklists if discovery.tracklists.any?
        if discovery.construction_editions.any?
          evidence["construction_editions"] = (Array(evidence["construction_editions"]) + discovery.construction_editions.values)
            .uniq { |edition| edition["id"] }
        end
        evidence["pending_original_group"] = discovery.pending_original_group if discovery.pending_original_group
      end
      broaden_recording_search(surface) if @adaptive && @discover
      if verified
        slot_check = {
          "requested_edition_mbid" => edition_id, "returned_edition_mbid" => edition&.fetch("id", nil),
          "title_matches" => edition.present? && edition["title"] == surface.album,
          "complete_media" => edition.present? && complete_edition?(edition),
          "matching_slots" => evidence["slots"].select { |slot| slot["recording_mbid"] == recording["id"] && slot["title"] == surface.track }
        }
        if !slot_check["title_matches"] || !slot_check["complete_media"] ||
            slot_check["returned_edition_mbid"] != edition_id || slot_check["matching_slots"].empty?
          reason("unverified_edition_slot", slot_check)
        end
      end

      compare_historical_fixture(surface, edition) if @discogs
      evidence["suggested_mbid"] = recording.fetch("id") if verified && evidence["reasons"].empty?
      evidence
    end

    private

    def recording_page(surface)
      feature = DiscoveryTitle.featured_credit(surface.track) if @workspace
      interpretation = evidence["title_interpretation"]
      if !feature && !interpretation && (id = @catalog_identity[:recording_mbid])
        data = @musicbrainz.verify_recording(@session, id, catalog: true)["data"]
        if data&.fetch("id", nil) == id
          return { "count" => 1, "offset" => 0, "recordings" => [ data ] }
        end
      end

      scope = @catalog_identity.slice(:artist_mbid)
      return search_surface(surface, surface.track, scope) unless feature || interpretation

      evidence["recording_searches"] = []
      pages = [ search_surface(surface, surface.track, scope) ]
      if feature
        title, guest = feature
        pages << search_surface(surface, title, scope, featured_artist: guest)
      end
      if interpretation
        base = interpretation.fetch("base_title")
        versioned = interpretation.fetch("descriptors").select { |descriptor| descriptor["kind"] == "version" }
        titles = [ ([ base ] + versioned.pluck("text")).join(" "), base ].uniq - [ surface.track, feature&.first ]
        titles.each { |title| pages << search_surface(surface, title, scope) }
      end
      recordings = pages.flat_map { |page| page.fetch("recordings") }.uniq { |row| row.fetch("id") }
      incomplete = evidence["recording_searches"].any? { |search| search.fetch("count") != search.fetch("returned") }
      { "count" => recordings.size, "offset" => 0, "recordings" => recordings, "incomplete" => incomplete }
    end

    def search_surface(surface, title, scope, **interpretation)
      page = search_page(surface, title, **scope, **interpretation)
      return page if scope.empty? || page.fetch("recordings").any?

      search_page(surface, title, **interpretation)
    end

    def search_page(surface, title, **options)
      page = @musicbrainz.candidate_page(@session, artist: surface.artist, title:, catalog: @workspace, **options)
      if (searches = evidence["recording_searches"])
        searches << { "query" => @session.current_request.dig("parameters", "query"),
          "count" => page.fetch("count"), "returned" => page.fetch("recordings").size }
      end
      page
    end

    def broaden_recording_search(surface)
      interpretation = evidence["title_interpretation"]
      reported_version = interpretation && !TitleInterpretation.mastering_only?(interpretation)
      credible = Ranking.call(surface, evidence, source_hints: true).any? do |rank|
        version = rank.dig("inputs", "version", "state")
        rank.dig("inputs", "title", "state") == "positive" && rank.dig("inputs", "artist_name", "state") == "positive" &&
          (reported_version ? version == "positive" : version != "contradictory")
      end
      return if credible

      alternatives = interpretation ? interpretation.fetch("alternatives").drop(2) : DiscoveryTitle.alternate_titles(surface.track).first(2)
      scoped = alternatives.map { |title| [ title, { artist: surface.artist } ] }
      # The album can recover different credit arrangements; require the credited
      # artist before retaining any of these hits.
      scoped << [ surface.track, { artist: nil, release: surface.album } ] if surface.album.present?
      evidence["adaptive_searches"] = []
      known = evidence.fetch("candidates").pluck("id").to_set
      scoped.each do |title, options|
        attempt = { "strategy" => options[:release] ? "title_and_album" : "alternate_title", "title" => title }
        evidence["adaptive_searches"] << attempt
        page = @musicbrainz.candidate_page(@session, title:, catalog: true, **options)
        attempt.merge!("count" => page["count"], "returned" => page.fetch("recordings").size,
          "query" => @session.current_request.dig("parameters", "query"))
        accepted = page.fetch("recordings").select do |row|
          DiscoveryTitle.credit_key(row["title"]) == DiscoveryTitle.credit_key(title) &&
            Array(row["artist-credit"]).any? do |credit|
              (@catalog_identity[:artist_mbid].present? && credit.dig("artist", "id") == @catalog_identity[:artist_mbid]) ||
                [ credit["name"], credit.dig("artist", "name") ].any? { |name| DiscoveryTitle.match?(name, surface.artist) }
            end
        end
        attempt["accepted_ids"] = accepted.pluck("id")
        accepted.first(5).each do |row|
          next unless known.add?(row.fetch("id"))

          evidence.fetch("candidates") << recording_evidence(row).merge("adaptive_search" => attempt.slice("strategy", "title", "query"))
        end
        # Retain alternatives for manual review; their presence is not identity proof.
        break if accepted.any? { |row| DiscoveryTitle.credit_key(surface.track) == DiscoveryTitle.credit_key(row["title"]) }
      end
    end

    def merge_discovered(discovered)
      by_id = discovered.group_by { |candidate| candidate["id"] }
      return if by_id.empty?

      evidence["discovery_appearances"] = by_id.transform_values { |rows| rows.pluck("release_discovery").uniq }
      additions = by_id.values.map do |rows|
        rows.find { |row| row.dig("release_discovery", "relationship") == "matching_catalog_caption" } || rows.first
      end.index_by { |row| row["id"] }
      evidence["candidates"] = evidence.fetch("candidates").map do |row|
        discovered = additions.delete(row["id"])
        discovered ? row.merge("release_discovery" => discovered.fetch("release_discovery")) : row
      end + additions.values
      if (verified = evidence["verified_recording"])
        appearance = evidence["candidates"].find { |row| row["id"] == verified["id"] }&.fetch("release_discovery", nil)
        verified["release_discovery"] = appearance if appearance
      end
    end

    def compare_historical_fixture(surface, edition)
      discogs = evidence["discogs"] = {}
      @discogs.compare(surface, edition, discogs)
      if discogs["incomplete_reasons"].present?
        reason("incomplete_discogs_evidence", "provider" => "discogs", "causes" => discogs["incomplete_reasons"])
      end
      if %w[contradicts mixed].include?(discogs["status"])
        reason("discogs_disagreement", "status" => discogs["status"],
          "release_ids" => discogs["releases"].select { |release| release["status"] == "track_absent" }.pluck("release_id"))
      end
    end

    def reason(code, details)
      evidence["reasons"] << code
      evidence["reason_details"][code] = details
    end

    def verified_recording?(recording, expected_id)
      recording && Clients::Musicbrainz::MBID.match?(recording["id"].to_s) &&
        recording["id"].casecmp?(expected_id.to_s)
    end

    def assess_identity(surface, claims, recording, candidates)
      credits = Array(recording["artist-credit"])
      artist_ids = credits.map { |credit| credit.dig("artist", "id") }
      if recording["title"] != surface.track || credit_name(credits) != surface.artist ||
          credits.empty? || credits.any? { |credit| credit.dig("artist", "name").blank? } ||
          artist_ids.any? { |id| !Clients::Musicbrainz::MBID.match?(id.to_s) } ||
          (claims["artist_mbid"].present? && !artist_ids.include?(claims["artist_mbid"]))
        reason("source_identity_conflict", "recording_mbid" => recording["id"], "catalog_title" => recording["title"],
          "catalog_credit" => credit_name(credits), "catalog_artist_mbids" => artist_ids)
      end
      if candidates.none? { |candidate| candidate["id"] == recording["id"] }
        reason("search_does_not_confirm_recording", "recording_mbid" => recording["id"])
      end
      competing = candidates.select do |candidate|
        candidate["id"] != recording["id"] && credit_name(Array(candidate["artist-credit"])) == surface.artist &&
          base_title(candidate["title"]) == base_title(surface.track)
      end
      if competing.any?
        reason("competing_recordings", "verified_mbid" => recording["id"], "candidate_mbids" => competing.pluck("id"))
      end
      markers = [ surface.album, surface.track ].filter_map { |text| text.to_s[VERSION_MARKER] }
      if recording["video"] || recording["disambiguation"].present? || markers.any?
        reason("unresolved_version", "video" => recording["video"], "disambiguation" => recording["disambiguation"],
          "source_markers" => markers)
      end
    end

    def base_title(title)
      title.to_s.sub(/\s*[(\[].*\z/, "")
    end

    def complete_edition?(edition)
      media = edition["media"]
      media.is_a?(Array) && media.any? && media.all? do |medium|
        medium["tracks"].is_a?(Array) && medium["track-count"] == medium["tracks"].size
      end
    end

    def edition_slots(edition)
      Array(edition&.fetch("media", nil)).flat_map do |medium|
        tracks = medium["tracks"]
        next [] unless tracks.is_a?(Array) && medium["track-count"] == tracks.size

        tracks.map do |track|
          { "medium" => medium["position"], "position" => track["position"], "track_mbid" => track["id"],
            "number" => track["number"], "length" => track["length"] || track.dig("recording", "length"),
            "title" => track["title"], "recording_mbid" => track.dig("recording", "id") }
        end
      end
    end

    def credit_name(credits)
      credits.map { |credit| "#{credit["name"]}#{credit["joinphrase"]}" }.join
    end

    def recording_evidence(recording)
      recording.slice("id", "title", "length", "disambiguation", "video", "isrcs", "artist-credit", "first-release-date").merge(
        "releases" => Array(recording["releases"]).map { |release| release.slice("id", "title", "country", "date", "release-group", "disambiguation") }
      )
    end
  end
end
