module Musicbrainz
  class RecordingSearch
    def self.call(artist:, recording:, release: nil)
      new(
        artist: artist,
        recording: recording,
        release: release
      ).call
    end

    def self.from_surface(surface)
      call(
        artist: surface.artist_name,
        recording: surface.track_name,
        release: surface.album_name
      )
    end

    def initialize(artist:, recording:, release:)
      @artist    = artist
      @recording = recording
      @release   = release
    end

    def call
      client.search_recordings(
        artist: artist,
        recording: recording,
        release: release
      )
    end

    private

    attr_reader :artist, :recording, :release

    def client
      @client ||= Clients::Musicbrainz.new
    end
  end
end
