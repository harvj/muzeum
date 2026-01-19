module Lastfm
  class Importer
    include SimpleLogger

    PER_PAGE = 200
    MAX_PAGES = 3

    def self.run!(username:, page_limit: MAX_PAGES)
      raise ArgumentError, "lastfm username required" if username.blank?

      user   = User.find_by!(lastfm_username: username)
      client = Lastfm::Client.new(username: user.lastfm_username)

      new(user, client: client).run(page_limit: page_limit)
    end

    def initialize(user, client:)
      @user = user
      @client = client
    end

    def run(page_limit: MAX_PAGES)
      log "Starting import for #{user.lastfm_username} (#{page_limit} pages)"
      @import_run = user.import_runs.create!(status: "running")

      page = 1
      total_inserted = 0
      range_start = nil
      range_end = nil
      from_ts = user.scrobbles.maximum(:played_at)&.to_i # get "from" timestamp param based on oldest stored scrobble time

      while page <= page_limit
        from_ts += 1 if from_ts

        # --- fetch first page to get total pages count
        raw_meta = client.recent_tracks(
          from: from_ts,
          limit: PER_PAGE
        )
        meta = RecentTracksParser.parse(raw_meta, no_tracks: true)
        record_notes(:meta, meta)

        break if meta[:total].to_i == 0

        # --- fetch oldest unstored page
        raw_tracks = client.recent_tracks(
          page: meta[:total_pages],
          from: from_ts,
          limit: PER_PAGE
        )
        parsed = RecentTracksParser.parse(raw_tracks)
        meta = parsed[:meta]
        tracks = parsed[:tracks]

        break if tracks.empty?

        # --- insert page of scrobbles into db
        inserted = insert_scrobbles(tracks)
        total_inserted += inserted
        skipped = tracks.size - inserted

        record_notes(:pages, {
          page: page,
          lastfm_page: meta[:page],
          lastfm_total_pages:  meta[:total_pages],
          lastfm_total: meta[:total],
          returned: tracks.size,
          inserted: inserted,
          skipped: skipped
        })

        log("page=#{meta[:page]} returned=#{tracks.size} inserted=#{inserted} skipped=#{skipped}")

        times = tracks.map { |t| t[:played_at] }.compact
        range_start ||= times.min
        range_end = times.max if times.any?

        page += 1
        from_ts = range_end.to_i # use current page range_end to set next "from" param
      end

      import_run.update!(
        status: "completed",
        scrobbles_processed: total_inserted,
        range_start_at: range_start,
        range_end_at: range_end
      )
      log("Import complete for #{user.lastfm_username} (#{page_limit} pages)")
    rescue => e
      record_notes(:errors, e.message)
      import_run.failed!
      raise
    end

    private

    attr_reader :user, :client, :import_run

    def record_notes(key, data)
      import_run.notes ||= {}
      import_run.notes[key.to_s] ||= []
      import_run.notes[key.to_s] << data
      import_run.save!
    end

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
