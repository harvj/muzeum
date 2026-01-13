module Lastfm
  class Importer
    def initialize(user, client: Lastfm::Client.new(user))
      @user = user
      @client = client
    end

    def run
      scrobbles = client.recent_scrobbles(since: user.last_imported_at)

      scrobbles.each do |scrobble|
        process_scrobble(scrobble)
      end

      update_cursor(scrobbles)
    end

    private

    attr_reader :user, :client

    def process_scrobble(scrobble)
      date = scrobble[:played_at].to_date

      artist = Artist.find_or_create_by!(name: scrobble[:artist]) do |a|
        a.mbid = scrobble[:artist_mbid]
        a.source = "lastfm"
        a.status = :provisional
        a.confidence = 0.3
      end

      recording = Recording.find_or_create_by!(title: scrobble[:name]) do |r|
        r.mbid = scrobble[:mbid]
        r.source = "lastfm"
        r.status = :provisional
        r.confidence = 0.3
      end

      RecordingArtist.find_or_create_by!(
        artist: artist,
        recording: recording
      )

      daily = DailyListen.find_or_initialize_by(
        user: user,
        recording: recording,
        date: date,
        year: date.year
      )

      daily.listen_count += 1
      daily.save!
    end

    def update_cursor(scrobbles)
      return if scrobbles.empty?

      latest = scrobbles.map { |s| s[:played_at] }.max
      user.update!(last_imported_at: latest)
    end
  end
end
