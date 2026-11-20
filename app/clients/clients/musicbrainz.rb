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

    def candidate_page(session, artist:, title:, offset: 0, catalog: false)
      params = { query: build_recording_query(artist:, recording: title, release: nil), limit: 25, offset:, fmt: "json" }
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

    def verify_recording(session, mbid, catalog: false)
      return { "status" => "invalid" } unless MBID.match?(mbid.to_s)

      params = { fmt: "json", inc: "artist-credits+releases+release-groups+isrcs" }
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
        fmt: "json", inc: catalog ? "recordings+artist-credits+release-groups+url-rels" : "recordings+artist-credits+release-groups"
      }, &projection)["data"]
    end

    def catalog_artist(session, mbid)
      return unless MBID.match?(mbid.to_s)

      session.get(:musicbrainz, "/ws/2/artist/#{mbid}", params: { fmt: "json" }) do |data|
        data.slice("id", "name", "country")
      end["data"]
    end

    # --- Private ----------------------------------------------------

    private

    def project_recording(data)
      data.slice("id", "title", "length", "video", "disambiguation", "first-release-date", "isrcs").merge(
        "artist-credit" => project_credits(data["artist-credit"]),
        "releases" => Array(data["releases"]).map { |release| release.slice("id", "title", "date", "country") })
    end

    def project_edition(data)
      result = data.slice("id", "title", "status", "country", "date")
      result["release-events"] = Array(data["release-events"]).filter_map do |event|
        codes = Array(event.dig("area", "iso-3166-1-codes"))
        { "country_codes" => codes } if codes.any?
      end
      result["release-group"] = data["release-group"]&.slice("id", "primary-type", "secondary-types", "first-release-date")
      result["artist-credit"] = project_credits(data["artist-credit"])
      result["relations"] = Array(data["relations"]).select { |relation| relation["type"] == "discogs" }.map do |relation|
        { "url" => relation.fetch("url").slice("resource") }
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
      parts << %(artist:"#{escape_phrase(artist)}")
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
