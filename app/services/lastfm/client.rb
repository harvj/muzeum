require "net/http"
require "uri"

module Lastfm
  class Client
    DEFAULT_LIMIT = 200

    def initialize(username:, api_key: ENV["LASTFM_API_KEY"], base_url: ENV["LASTFM_API_BASE"])
      @username = username
      @api_key = api_key
      @base_url = base_url
    end

    def recent_tracks(page: nil, from:, limit: DEFAULT_LIMIT)
      uri = URI(base_url)

      params = {
        method: "user.getrecenttracks",
        user: username,
        api_key: api_key,
        format: "xml",
        limit: limit
      }

      params[:page] = page if page.present?
      params[:from] = from if from.present?

      uri.query = URI.encode_www_form(params)

      Rails.logger.info("[Lastfm::Client] #{uri.query}")

      response = Net::HTTP.get_response(uri)

      unless response.is_a?(Net::HTTPSuccess)
        raise Lastfm::Error.new(
          "Last.fm request failed",
          status: response.code,
          body: response.body
        )
      end

      response.body
    end

    private

    attr_reader :username, :api_key, :base_url
  end
end
