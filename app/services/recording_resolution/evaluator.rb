module RecordingResolution
  class Evaluator
    VERSION = "recording-evidence-v1"
    VERSION_MARKER = /\b(live|remix|remixed|acoustic|demo|alternate|edit|instrumental|take)\b/i

    def initialize(session, discogs:)
      @session = session
      @discogs = discogs
      @musicbrainz = Clients::Musicbrainz.new
    end

    def call(surface, claims)
      return { "reasons" => [ "missing_title_or_artist" ] } if surface.track.blank? || surface.artist.blank?

      page = @musicbrainz.candidate_page(@session, artist: surface.artist, title: surface.track)
      candidates = page.fetch("recordings")
      verification = claims["track_mbid"].present? ? @musicbrainz.verify_recording(@session, claims["track_mbid"]) : {}
      recording = verification["data"]
      releases = Array(recording&.fetch("releases", nil))
      edition_id = claims["album_mbid"].presence || releases.find { |release| release["title"] == surface.album }&.fetch("id", nil)
      edition = @musicbrainz.edition(@session, edition_id) if edition_id && surface.album.present?
      slots = edition_slots(edition)
      discogs = discogs_evidence(surface, edition)
      reasons = reasons_for(surface, claims, page, verification, edition, edition_id, slots, discogs)
      {
        "source_claims" => claims, "search" => page.slice("count", "offset"),
        "candidates" => candidates.map { |candidate| recording_evidence(candidate) },
        "verification" => verification.except("data"), "verified_recording" => recording && recording_evidence(recording),
        "edition" => edition&.slice("id", "title", "release-group", "country", "date"),
        "slots" => slots, "discogs" => discogs, "reasons" => reasons,
        "suggested_mbid" => reasons.empty? ? recording.fetch("id") : nil
      }
    end

    private

    def reasons_for(surface, claims, page, verification, edition, edition_id, slots, discogs)
      recording = verification["data"]
      reasons = []
      reasons << "incomplete_search" if page["count"] != page["recordings"].size
      reasons << "missing_album" if surface.album.blank?
      reasons << "missing_source_mbid" if claims["track_mbid"].blank?
      unless recording && Clients::Musicbrainz::MBID.match?(recording["id"].to_s) &&
          recording["id"].casecmp?(verification["redirected_to"] || claims["track_mbid"].to_s)
        return reasons << "unverified_recording"
      end

      reasons.concat(identity_reasons(surface, claims, recording, page["recordings"]))
      if edition.blank? || !complete_edition?(edition) || edition["title"] != surface.album ||
          edition["id"] != edition_id ||
          !slots.any? { |slot| slot["recording_mbid"] == recording["id"] && slot["title"] == surface.track }
        reasons << "unverified_edition_slot"
      end
      reasons << "incomplete_discogs_evidence" if discogs["status"] == "incomplete"
      reasons << "discogs_disagreement" if discogs["status"] == "contradicts"
      reasons
    end

    def identity_reasons(surface, claims, recording, candidates)
      reasons = []
      credits = Array(recording["artist-credit"])
      if recording["title"] != surface.track || credit_name(credits) != surface.artist ||
          credits.empty? || credits.any? { |credit|
            credit.dig("artist", "name").blank? || !Clients::Musicbrainz::MBID.match?(credit.dig("artist", "id").to_s)
          } ||
          (claims["artist_mbid"].present? && credits.none? { |credit| credit.dig("artist", "id") == claims["artist_mbid"] })
        reasons << "source_identity_conflict"
      end
      if candidates.none? { |candidate| candidate["id"] == recording["id"] }
        reasons << "search_does_not_confirm_recording"
      end
      if candidates.any? { |candidate| candidate["id"] != recording["id"] &&
          credit_name(Array(candidate["artist-credit"])) == surface.artist &&
          candidate["title"].to_s.sub(/\s*[(\[].*\z/, "") == surface.track.to_s.sub(/\s*[(\[].*\z/, "") }
        reasons << "competing_recordings"
      end
      if recording["video"] || recording["disambiguation"].present? || [ surface.album, surface.track ].any? { |text| VERSION_MARKER.match?(text.to_s) }
        reasons << "unresolved_version"
      end
      reasons
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
            "title" => track["title"], "recording_mbid" => track.dig("recording", "id") }
        end
      end
    end

    def credit_name(credits)
      credits.map { |credit| "#{credit["name"]}#{credit["joinphrase"]}" }.join
    end

    def recording_evidence(recording)
      recording.slice("id", "title", "length", "disambiguation", "video", "isrcs", "artist-credit", "first-release-date").merge(
        "releases" => Array(recording["releases"]).map { |release| release.slice("id", "title", "country", "date", "release-group") }
      )
    end

    def discogs_evidence(surface, musicbrainz_edition)
      return { "status" => "no_album_context" } if surface.album.blank?

      result = @discogs.search_release(artist: surface.artist, title: surface.album)
      return { "status" => "incomplete" } unless result

      matches = result.fetch("results").select { |item| item["title"] == "#{surface.artist} - #{surface.album}" }
      return { "status" => "incomplete" } if result.dig("pagination", "pages").to_i > 1 || matches.size > 1
      return { "status" => "no_matching_release" } if matches.empty?

      edition = @discogs.release(matches.first.fetch("id"))
      return { "status" => "incomplete" } unless edition && edition["title"] == surface.album &&
        edition.fetch("artists").map { |artist| "#{artist["anv"].presence || artist["name"]}#{artist["join"]}" }.join == surface.artist

      matching_slots = edition.fetch("tracklist").select { |track| track["type_"] == "track" && track["title"] == surface.track }
      # Retain derived comparisons and references. Catalog display would need a fresh response and attribution.
      { "status" => matching_slots.any? ? "corroborates" : "contradicts",
        "release_id" => edition.fetch("id"), "master_id" => edition["master_id"],
        "slot_count" => matching_slots.size,
        "country_agreement" => agreement(edition["country"], musicbrainz_edition&.fetch("country", nil)),
        "release_year_agreement" => agreement(edition["year"]&.to_s, musicbrainz_edition&.fetch("date", nil)&.slice(0, 4)) }
    end

    def agreement(left, right)
      left == right if left.present? && right.present?
    end
  end
end
