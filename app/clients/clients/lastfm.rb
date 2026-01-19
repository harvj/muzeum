# app/clients/clients/lastfm.rb

require "http"
require "json"

module Clients
  class Lastfm
    include SimpleLogger

    BASE_URL = "https://ws.audioscrobbler.com/2.0/".freeze
    DEFAULT_LIMIT = 200

    DEFAULT_TIMEOUTS = {
      connect: 5,
      read: 10,
      write: 5
    }.freeze

    def initialize(username:)
      @username = username
    end

    attr_reader :username

    # --- Public API -------------------------------------------------

    def recent_tracks(page: nil, from: nil, limit: DEFAULT_LIMIT)
      params = {
        method: "user.getrecenttracks",
        user: username,
        limit: limit
      }

      params[:page] = page if page.present?
      params[:from] = from if from.present?

      get(params)
    end

    # --- Private ----------------------------------------------------

    private

    def http
      @http ||= HTTP
        .timeout(DEFAULT_TIMEOUTS)
        .headers("User-Agent" => user_agent)
    end

    def get(params)
      query = base_params.merge(params)
      log("Requesting #{redact(query.to_query, :api_key)}")

      response = http.get(BASE_URL, params: query)
      handle_response(response)
    rescue HTTP::TimeoutError, HTTP::ConnectionError => e
      raise Clients::NetworkError, e.message
    end

    def handle_response(response)
      case response.code
      when 200
        response.to_s
      when 401
        raise Clients::Unauthorized
      when 429
        raise Clients::RateLimited
      else
        raise Clients::InvalidResponse,
              "Last.fm returned #{response.code}"
      end
    end

    def base_params
      {
        api_key: api_key,
        format: "xml"
      }
    end

    def api_key
      ENV.fetch("LASTFM_API_KEY")
    end

    def user_agent
      "muzeum.fm/0.1"
    end
  end
end
