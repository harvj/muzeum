module CatalogFixtures
  IDS = RecordingResolution::FixtureTransport::IDS

  def catalog_observation(user, time: Time.current)
    Scrobble.create!(user:, lastfm_account: user.source_account, played_at: time, source_fingerprint: SecureRandom.hex(32),
      payload: { artist_name: "Night Lines", album_name: "Night Drive", track_name: "Signals",
        track_mbid: IDS[:studio], album_mbid: IDS[:edition] })
  end

  def catalog_assessment(observation)
    archive = observation.lastfm_account
    pilot = RecordingResolution::PilotRunner.start!(archive_id: archive.id, upper_id: observation.id)
    RecordingResolution::PilotRunner.select!(pilot)
    RecordingResolution::Work.where(pilot_id: pilot.id).find_each { |work| RecordingResolution::Processor.new(work).call }
    RecordingResolution::Assessment.find(RecordingResolution::Work.where(pilot_id: pilot.id).first.assessment_id)
  end

  class Session
    attr_reader :provenance, :paths
    attr_accessor :artist_data

    def initialize
      @provenance = []
      @paths = []
      @artist_data = { "id" => IDS[:artist], "name" => "Night Lines", "country" => "US" }
    end

    def get(provider, path, params:, **)
      @paths << path
      @provenance << { "provider" => provider.to_s, "endpoint" => path, "parameters" => params.stringify_keys }
      data = case path
      when "/ws/2/artist/#{IDS[:artist]}"
        artist_data
      when "/ws/2/release/#{IDS[:edition]}"
        edition
      else
        fixture = RecordingResolution::FixtureTransport.new
        status, _, body = fixture.call(provider, path, params)
        return { "status" => status } if status != 200

        JSON.parse(body)
      end
      { "data" => block_given? ? yield(data) : data }
    end

    def edition
      credit = { "name" => "Night Lines", "artist" => { "id" => IDS[:artist], "name" => "Night Lines" } }
      studio = { "id" => IDS[:studio], "title" => "Signals", "length" => 190_000, "artist-credit" => [ credit ] }
      other = { "id" => IDS[:other], "title" => "Different Song", "length" => 120_000, "artist-credit" => [ credit ] }
      new_track = ->(recording, position, track_id) do
        { "id" => track_id, "title" => recording["title"], "position" => position, "number" => position.to_s, "recording" => recording }
      end
      { "id" => IDS[:edition], "title" => "Night Drive", "date" => "2020-06", "country" => "US", "status" => "Official",
        "artist-credit" => [ credit ], "release-group" => { "id" => IDS[:release_group], "primary-type" => "Album",
          "secondary-types" => [], "first-release-date" => "2020-06" },
        "media" => [ { "position" => 1, "track-count" => 2, "tracks" => [
          new_track.call(studio, 1, IDS[:track]), new_track.call(other, 2, IDS[:other])
        ] }, { "position" => 2, "track-count" => 1, "tracks" => [ new_track.call(studio, 1, IDS[:studio]) ] } ] }
    end
  end
end
