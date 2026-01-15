module Lastfm
  class Importer
    PER_PAGE = 200
    MAX_PAGES = 1

    def initialize(user, client:)
      @user = user
      @client = client
    end

    def run
      import_run = user.import_runs.create!(status: "running")

      page = 1
      total_inserted = 0
      range_start = nil
      range_end = nil
      from_ts = user.scrobbles.maximum(:played_at)&.to_i

      while page <= MAX_PAGES
        meta = client.recent_tracks(page: page, limit: PER_PAGE)
        total_pages = RecentTracksParser.parse_meta(meta)[:total_pages]

        xml = client.recent_tracks(page: total_pages, limit: PER_PAGE)
        tracks = RecentTracksParser.parse_tracks(xml)

        break if tracks.empty?

        inserted = insert_scrobbles(tracks)
        total_inserted += inserted

        times = tracks.map { |t| t[:played_at] }.compact
        range_start ||= times.min
        range_end = times.max if times.any?

        page += 1
      end

      import_run.update!(
        status: "completed",
        scrobbles_processed: total_inserted,
        range_start_at: range_start,
        range_end_at: range_end
      )
    rescue => e
      import_run.update!(status: "failed", notes: { error: e.message })
      raise
    end

    private

    attr_reader :user, :client

    def insert_scrobbles(tracks)
      rows = tracks.filter_map do |track|
        next unless track[:played_at]

        {
          user_id: user.id,
          played_at: track[:played_at],
          payload: track,
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      result = Scrobble.insert_all(
        rows,
        unique_by: :index_scrobbles_on_user_and_played_at
      )

      result.rows.count
    end
  end
end
