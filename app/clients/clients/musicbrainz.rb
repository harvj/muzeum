require "http"
require "json"

module Clients
  require_relative "error"

  class Musicbrainz
    include SimpleLogger

    BASE_URL   = "https://musicbrainz.org/ws/2".freeze
    USER_AGENT = "muzeum.fm/0.1 (jimrharvey@gmail.com)".freeze

    DEFAULT_TIMEOUTS = {
      connect: 5,
      read: 10,
      write: 5
    }.freeze

    # --- Public API -------------------------------------------------

    def search_recordings(artist:, recording:, release: nil, limit: 10)
      raise ArgumentError, "artist required" if artist.blank?
      raise ArgumentError, "recording required"  if recording.blank?

      query = build_recording_query(
        artist: artist,
        recording: recording,
        release: release
      )

      response = get(
        "/recording",
        query: {
          query: query,
          limit: limit,
          fmt: "json"
        }
      )

      response.fetch("recordings", [])
    end

    def fetch_recording(mbid)
      get(
        "/recording/#{mbid}",
        query: {
          fmt: "json",
          inc: [
            "artists",
            "artist-credits",
            "media",
            "releases",
            "release-groups",
            "isrcs",
            "tags"
          ].join("+")
        }
      )
    end

    def fetch_release(mbid)
      get(
        "/release/#{mbid}",
        query: {
          fmt: "json",
          inc: [
            "artists",
            "artist-credits",
            "labels",
            "recordings",
            "media",
            "release-groups",
            "tags"
          ].join("+")
        }
      )
    end

    def fetch_artist(mbid)
      get(
        "/artist/#{mbid}",
        query: {
          fmt: "json",
          inc: [
            "aliases",
            "tags",
            "genres"
          ].join("+")
        }
      )
    end

    MBID = /\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i

    def candidate_page(session, artist:, title:, offset: 0, catalog: false, artist_mbid: nil, featured_artist: nil, release: nil)
      query = build_recording_query(artist:, recording: title, release:)
      query = %(arid:#{artist_mbid} AND recording:"#{escape_phrase(title)}") if MBID.match?(artist_mbid.to_s)
      query += %( AND artist:"#{escape_phrase(featured_artist)}") if featured_artist.present?
      params = { query:, limit: 25, offset:, fmt: "json" }
      session.get(:musicbrainz, "/ws/2/recording", params:) do |data|
        unless data["count"].is_a?(Integer) && data["offset"] == offset && data["recordings"].is_a?(Array) &&
            data["recordings"].all? { |recording| recording.is_a?(Hash) && MBID.match?(recording["id"].to_s) }
          raise RecordingResolution::ProviderError, "MusicBrainz search envelope is incomplete"
        end

        if catalog
          data.slice("count", "offset").merge("recordings" => data.fetch("recordings").map { |recording| project_recording(recording) })
        else
          data
        end
      end.fetch("data") { raise RecordingResolution::ProviderError, "MusicBrainz search endpoint unavailable" }
    end

    def release_candidates(session, artist:, title:, artist_mbid: nil)
      query = "artist:\"#{escape_phrase(artist)}\" AND release:\"#{escape_phrase(title)}\""
      query = %(arid:#{artist_mbid} AND release:"#{escape_phrase(title)}") if MBID.match?(artist_mbid.to_s)
      response = session.get(:musicbrainz, "/ws/2/release", params: { fmt: "json", limit: 5, query: }) do |data|
        releases = data["releases"]
        raise RecordingResolution::ProviderError, "MusicBrainz release search envelope is incomplete" unless releases.is_a?(Array)

        { "releases" => releases.first(5).map { |release| release.slice("id", "title", "disambiguation") } }
      end
      Array(response.dig("data", "releases"))
    end

    def verify_recording(session, mbid, catalog: false)
      return { "status" => "invalid" } unless MBID.match?(mbid.to_s)

      params = { fmt: "json", inc: "artist-credits+releases+release-groups+isrcs" }
      params[:inc] += "+genres+tags+recording-rels" if catalog
      projection = method(:project_recording) if catalog
      first = session.get(:musicbrainz, "/ws/2/recording/#{mbid.downcase}", params:, &projection)
      return first unless first["redirect"]

      session.get(:musicbrainz, "/ws/2/recording/#{first.fetch("redirect")}", params:, &projection)
        .merge("redirected_from" => mbid, "redirected_to" => first.fetch("redirect"))
    end

    def edition(session, mbid, catalog: false)
      return unless MBID.match?(mbid.to_s)

      projection = method(:project_edition) if catalog
      session.get(:musicbrainz, "/ws/2/release/#{mbid}", params: {
        fmt: "json", inc: catalog ? "recordings+artist-credits+release-groups+url-rels+release-rels+genres+tags+isrcs" : "recordings+artist-credits+release-groups"
      }, &projection)["data"]
    end

    def collection_editions(session, group_mbid, limit:)
      browse_releases(session, { "release-group" => group_mbid }, limit:)
    end

    def recording_releases(session, mbid, limit:)
      browse_releases(session, { recording: mbid, inc: "release-groups+media" }, limit:)
    end

    def provenance_recording(session, mbid)
      return unless MBID.match?(mbid.to_s)

      inc = "artist-credits+isrcs+recording-rels+work-rels+artist-rels+place-rels+annotation+release-groups+releases"
      session.get(:musicbrainz, "/ws/2/recording/#{mbid}", params: { fmt: "json", inc: }) do |data|
        relationships = Array(data["relations"]).filter_map do |relation|
          target = relation["target-type"]
          next unless target.in?(%w[recording work artist place]) && MBID.match?(relation.dig(target, "id").to_s)

          relation.slice("type", "type-id", "direction", "attributes", "begin", "end").merge(
            "target_type" => target, "target" => relation.fetch(target).slice("id", "name", "title"))
        end
        project_recording(data).merge("relationships" => relationships, "annotation" => data["annotation"])
      end["data"]
    end

    def provenance_releases(session, mbid, &progress)
      browse_releases(session, { recording: mbid, inc: "release-groups+media" }, limit: 25, &progress)
    end

    def catalog_artist(session, mbid)
      return unless MBID.match?(mbid.to_s)

      session.get(:musicbrainz, "/ws/2/artist/#{mbid}", params: { fmt: "json", inc: "url-rels+genres+tags" }) do |data|
        urls = Array(data["relations"]).select { |relation| relation["type"] == "wikidata" }.filter_map do |relation|
          relation.dig("url", "resource").to_s[%r{\Ahttps://www\.wikidata\.org/wiki/(Q[1-9][0-9]{0,11})\z}, 1]
        end.uniq
        data.slice("id", "name", "country", "area", "begin-area", "genres", "tags").merge("wikidata_ids" => urls.first(12))
      end["data"]
    end

    # --- Private ----------------------------------------------------

    private

    def browse_releases(session, relationship, limit:)
      releases = []
      count = nil
      pages = 0
      loop do
        params = { fmt: "json" }.merge(relationship).merge(limit:)
        params[:offset] = releases.length if releases.any?
        response = session.get(:musicbrainz, "/ws/2/release", params:) do |data|
          rows = data["releases"]
          data.slice("release-count", "release-offset").merge("releases" => rows.map { |row| release_reference(row) }) if rows.is_a?(Array)
        end["data"]
        rows = response&.fetch("releases", nil)
        total = response&.fetch("release-count", nil)
        unless rows.is_a?(Array) && total.is_a?(Integer) && total >= 0 && (block_given? || total <= 100) &&
            (count.nil? || count == total) && response.fetch("release-offset", releases.length) == releases.length &&
            releases.length + rows.length <= total && rows.all? { |row| MBID.match?(row["id"].to_s) } &&
            (rows.any? || releases.length == total)
          raise CanonicalCatalog::Store::Unverified, "Release browse is incomplete or exceeds the evidence budget"
        end
        count = total
        releases.concat(rows)
        if releases.pluck("id").uniq.size != releases.size
          raise CanonicalCatalog::Store::Unverified, "Release browse repeated an edition"
        end
        pages += 1
        yield releases.dup if block_given?
        return releases if releases.length == count
        if block_given? && (count > 100 || pages >= 5)
          raise CanonicalCatalog::Store::Unverified, "Release browse exceeds the evidence budget"
        end
      end
    end

    def release_reference(data)
      data.slice("id", "title", "date", "country", "status", "disambiguation", "packaging", "barcode").merge(
        "release-group" => data["release-group"]&.slice("id", "title", "primary-type", "secondary-types", "first-release-date"),
        "media" => Array(data["media"]).map { |medium| medium.slice("position", "format", "track-count") })
    end

    def project_recording(data)
      data.slice("id", "title", "length", "video", "disambiguation", "first-release-date", "isrcs", "genres", "tags").merge(
        "artist-credit" => project_credits(data["artist-credit"]),
        "edit_recording_mbids" => Array(data["relations"]).filter_map do |relation|
          relation.dig("recording", "id") if relation["type-id"] == "ce01b3ac-dd47-4702-9302-085344f96e84"
        end,
        "releases" => Array(data["releases"]).map do |release|
          release.slice("id", "title", "date", "country", "disambiguation", "status").merge(
            "release-group" => release["release-group"]&.slice("id", "title", "primary-type", "secondary-types", "first-release-date"))
        end)
    end

    def project_edition(data)
      result = data.slice("id", "title", "status", "country", "date", "disambiguation", "packaging", "genres", "tags")
      result["release-events"] = Array(data["release-events"]).filter_map do |event|
        codes = Array(event.dig("area", "iso-3166-1-codes"))
        { "country_codes" => codes } if codes.any?
      end
      result["release-group"] = data["release-group"]&.slice("id", "title", "primary-type", "secondary-types", "first-release-date")
      result["artist-credit"] = project_credits(data["artist-credit"])
      result["relations"] = Array(data["relations"]).select { |relation| relation["type"] == "discogs" }.map do |relation|
        { "url" => relation.fetch("url").slice("resource") }
      end
      result["edition_relationships"] = Array(data["relations"]).filter_map do |relation|
        next unless relation["target-type"] == "release" && MBID.match?(relation.dig("release", "id").to_s)

        relation.slice("type", "direction", "attributes", "begin", "end").merge(
          "release" => relation["release"].slice("id", "title"))
      end
      result["media"] = Array(data["media"]).map do |medium|
        medium.slice("position", "track-count", "format").merge("extra-track-layout" => medium["pregap"].present? || medium["data-tracks"].present?,
          "tracks" => medium["tracks"]&.map do |track|
          track.slice("id", "position", "number", "title", "length").merge(
            "artist-credit" => project_credits(track["artist-credit"]),
            "recording" => track["recording"] && project_recording(track["recording"]).except("releases"))
        end)
      end
      result
    end

    def project_credits(credits)
      Array(credits).map do |credit|
        credit.slice("name", "joinphrase").merge("artist" => credit.fetch("artist").slice("id", "name", "country"))
      end
    end

    def build_recording_query(artist:, recording:, release:)
      parts = []
      parts << %(artist:"#{escape_phrase(artist)}") if artist.present?
      parts << %(recording:"#{escape_phrase(recording)}")
      parts << %(release:"#{escape_phrase(release)}") if release.present?
      parts.join(" AND ")
    end

    def escape_phrase(value)
      value.gsub(/["\\]/) { |character| "\\#{character}" }
    end

    def http
      @http ||= HTTP
        .timeout(**DEFAULT_TIMEOUTS)
        .headers("User-Agent" => USER_AGENT)
    end

    def get(path, query:)
      log("Requesting #{[ path, query.to_query ].join("?")}")
      response = http.get("#{BASE_URL}#{path}", params: query)
      handle_response(response)
    rescue HTTP::TimeoutError, HTTP::ConnectionError => e
      raise Clients::NetworkError, e.message
    end

    def handle_response(response)
      case response.code
      when 200
        JSON.parse(response.to_s)
      when 401
        raise Clients::Unauthorized
      when 429
        raise Clients::RateLimited
      else
        raise Clients::InvalidResponse,
              "MusicBrainz returned #{response.code}"
      end
    end
  end
end
