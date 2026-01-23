class ScrobbleResolver
  include SimpleLogger

  def self.resolve!(scrobble)
    new(scrobble).resolve!
  end

  def initialize(scrobble)
    @scrobble = scrobble
  end

  attr_reader :scrobble

  def resolve!
    return scrobble if scrobble.recording_id.present?

    payload = scrobble.payload
    payload = JSON.parse(payload) if payload.is_a?(String)

    artist_name = payload.fetch("artist_name")
    track_name  = payload.fetch("track_name")
    album_name  = payload.fetch("album_name")

    artist_mbid = payload["artist_mbid"]
    track_mbid  = payload["track_mbid"]
    album_mbid  = payload["album_mbid"]

    normalized_key = RecordingSurface.normalize(artist_name, album_name, track_name)

    surface = RecordingSurface.find_by(normalized_key: normalized_key)

    if surface
      reinforce_surface!(surface)
      scrobble.update!(recording: surface.recording, recording_surface: surface)
      return scrobble
    end

    surface = RecordingSurface.create!(
      artist_name: artist_name,
      track_name: track_name,
      album_name: album_name,

      artist_mbid: artist_mbid,
      track_mbid: track_mbid,
      album_mbid: album_mbid,

      normalized_key: normalized_key,
      observed_count: 1
    )

    scrobble.update!(recording_surface: surface)
    scrobble
  end

  private

  def reinforce_surface!(surface)
    log("reinforce: Surface [#{surface.normalized_key}] matches Recording id: #{surface.recording_id}")
    surface.increment!(:observed_count)
  end
end
