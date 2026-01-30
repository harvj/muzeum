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

    # --- Private ----------------------------------------------------

    private

    def build_recording_query(artist:, recording:, release:)
      parts = []
      parts << %(artist:"#{artist}")
      parts << %(recording:"#{recording}")
      parts << %(release:"#{release}") if release.present?
      parts.join(" AND ")
    end

    def http
      @http ||= HTTP
        .timeout(DEFAULT_TIMEOUTS)
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
