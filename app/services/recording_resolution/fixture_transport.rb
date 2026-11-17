module RecordingResolution
  class FixtureTransport
    IDS = {
      studio: "550e8400-e29b-41d4-a716-446655440001",
      other: "550e8400-e29b-41d4-a716-446655440002",
      redirect: "550e8400-e29b-41d4-a716-446655440003",
      artist: "550e8400-e29b-41d4-a716-446655440004",
      edition: "550e8400-e29b-41d4-a716-446655440005",
      track: "550e8400-e29b-41d4-a716-446655440006",
      release_group: "550e8400-e29b-41d4-a716-446655440007"
    }.freeze

    def initialize(example = {})
      @example = example
    end

    def call(provider, path, params)
      if provider == :musicbrainz && path.end_with?(IDS[:redirect])
        return [ 301, { "Location" => "/ws/2/recording/#{IDS[:studio]}" }, "" ]
      end

      document = provider == :musicbrainz ? musicbrainz(path, params) : discogs(path)
      [ document ? 200 : 404, {}, document.to_json ]
    end

    private

    def musicbrainz(path, params)
      case path
      when "/ws/2/recording"
        candidates = params[:query].include?('artist:"Night Lines"') ? [ recording ] : []
        candidates << recording.merge("id" => IDS[:other], "title" => @example["alternative"]) if @example["alternative"]
        { "count" => @example["count"] || candidates.size, "offset" => params.fetch(:offset), "recordings" => candidates }
      when "/ws/2/recording/#{IDS[:studio]}"
        recording
      when "/ws/2/recording/#{IDS[:other]}"
        recording.merge("id" => IDS[:other], "title" => "Different Song")
      when "/ws/2/release/#{IDS[:edition]}"
        edition.merge("media" => [
          { "position" => 1, "track-count" => 1, "tracks" => [
            { "position" => 1, "id" => IDS[:track], "title" => "Signals", "recording" => { "id" => IDS[:studio] } }
          ] }
        ])
      end
    end

    def recording
      { "id" => IDS[:studio], "title" => "Signals", "length" => 190_000, "video" => false, "disambiguation" => "",
        "artist-credit" => [ { "name" => "Night Lines", "joinphrase" => "",
          "artist" => { "id" => IDS[:artist], "name" => "Night Lines" } } ], "releases" => [ edition ] }
    end

    def edition
      { "id" => IDS[:edition], "title" => "Night Drive", "country" => "US", "date" => "2020-06",
        "release-group" => { "id" => IDS[:release_group] } }
    end

    def discogs(path)
      case path
      when "/database/search"
        { "pagination" => { "page" => 1, "pages" => 1, "items" => 1, "per_page" => 25 },
          "results" => [ { "id" => 123, "master_id" => 12, "title" => "Night Lines - Night Drive" } ] }
      when "/releases/123"
        { "id" => 123, "master_id" => 12, "title" => "Night Drive", "country" => "US", "year" => 2020,
          "artists" => [ { "id" => 42, "name" => "Night Lines" } ],
          "tracklist" => [ { "position" => "A1", "type_" => "track", "title" => @example.fetch("discogs_track", "Signals") } ] }
      end
    end
  end
end
