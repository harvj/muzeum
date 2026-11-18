module Clients
  class Discogs
    NOTICE = "This application uses Discogs’ API but is not affiliated with, sponsored or endorsed by Discogs. ‘Discogs’ is a trademark of Zink Media, LLC."
    ATTRIBUTION = "Data provided by Discogs."
    SEARCH_PAGE_SIZE = 25

    def initialize(session, live:)
      @session = session
      @headers = {}
      return unless live

      key, secret = ENV.values_at("DISCOGS_CONSUMER_KEY", "DISCOGS_CONSUMER_SECRET")
      unless [ key, secret ].all? { |value| value&.match?(/\A[a-zA-Z0-9]+\z/) }
        raise RecordingResolution::ProviderError.new("Discogs application credentials are missing or malformed", terminal: true)
      end

      @headers["Authorization"] = "Discogs key=#{key}, secret=#{secret}"
    end

    def search_release(artist:, title:, page: 1)
      search({ type: "release", artist:, release_title: title }, page)
    end

    def search_artist(name:, page: 1)
      search({ type: "artist", q: name }, page)
    end

    def release(id)
      get("/releases/#{Integer(id)}") do |data|
        data.slice("id", "master_id", "title", "country", "year", "released").merge(
          "artists" => credits(data.fetch("artists")),
          "tracklist" => tracks(data.fetch("tracklist"))
        )
      end
    end

    def master(id)
      get("/masters/#{Integer(id)}") { |data| data.slice("id", "main_release", "title", "year") }
    end

    def versions(id, page: 1)
      get("/masters/#{Integer(id)}/versions", page:, per_page: 25) do |data|
        page_subset(data, "versions", %w[id title country released])
      end
    end

    private

    def search(params, page)
      get("/database/search", **params, page:, per_page: SEARCH_PAGE_SIZE) do |data|
        page_subset(data, "results", %w[id title country year master_id])
      end
    end

    def get(path, **params, &block)
      @session.get(:discogs, path, params:, headers: @headers, &block)["data"]
    end

    def page_subset(data, key, fields)
      { "pagination" => data.fetch("pagination").slice("page", "pages", "items", "per_page"),
        key => data.fetch(key).map { |item| item.slice(*fields) } }
    end

    def credits(items)
      items.map { |item| item.slice("id", "name", "anv", "join") }
    end

    def tracks(items)
      items.map do |item|
        item.slice("position", "title", "type_", "duration").tap do |track|
          track["artists"] = credits(item["artists"]) if item["artists"]
          track["sub_tracks"] = tracks(item["sub_tracks"]) if item["sub_tracks"]
        end
      end
    end
  end
end
