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

    def recent_tracks(page: nil, from: nil, limit: DEFAULT_LIMIT, to: nil)
      params = {
        method: "user.getrecenttracks",
        user: username,
        limit: limit
      }

      params[:to] = to if to.present?
      params[:page] = page if page.present?
      params[:from] = from if from.present?

      get(params)
    end

    def public_username!
      raw = get(method: "user.getinfo", user: username)
      doc = Nokogiri::XML(raw) { |config| config.strict.nonet }
      name = doc.at_xpath("/lfm/user/name")&.text
      raise Clients::InvalidResponse if name.blank? || doc.at_xpath("/lfm")&.[]("status") != "ok"
      name
    rescue Nokogiri::XML::SyntaxError
      raise Clients::InvalidResponse
    end

    # --- Private ----------------------------------------------------

    private

    def http
      @http ||= HTTP
        .timeout(**DEFAULT_TIMEOUTS)
        .headers("User-Agent" => user_agent)
    end

    def get(params)
      query = base_params.merge(params)
      log("Requesting #{redact(query.to_query, :api_key)}")

      ::Lastfm::RequestBudget.acquire!
      response = http.get(BASE_URL, params: query)
      handle_response(response)
    rescue HTTP::TimeoutError, HTTP::ConnectionError => e
      raise Clients::NetworkError, "Last.fm transport failed"
    end

    def handle_response(response)
      case response.code
      when 200
        body = response.to_s
        doc = Nokogiri::XML(body) { |config| config.strict.nonet }
        error = doc.at_xpath("/lfm/error")
        if error
          case error["code"].to_i
          when 29
            ::Lastfm::RequestBudget.cooldown!(60)
            raise Clients::RateLimited.new(60, raw_body: body)
          when 11, 16
            raise Clients::NetworkError.new(raw_body: body)
          when 4, 9, 10, 13, 26
            raise Clients::Unauthorized.new(raw_body: body)
          else
            # Keep the raw error envelope as immutable fetch evidence downstream.
            return body
          end
        end
        body
      when 401
        raise Clients::Unauthorized.new(raw_body: response.to_s)
      when 429
        raw_delay = response.headers["Retry-After"].to_s
        seconds = if raw_delay.match?(/\A\d+\z/)
          raw_delay.to_i
        else
          begin
            [ Time.httpdate(raw_delay) - Time.current, 1 ].max.ceil
          rescue ArgumentError
            60
          end
        end
        ::Lastfm::RequestBudget.cooldown!(seconds)
        raise Clients::RateLimited.new(seconds, raw_body: response.to_s)
      when 500..599
        raise Clients::NetworkError.new(raw_body: response.to_s)
      else
        raise Clients::InvalidResponse,
              "Last.fm returned #{response.code}"
      end
    rescue Nokogiri::XML::SyntaxError
      response.to_s # Persist malformed body before SourcePage rejects it.
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
