require "digest"

module Lastfm
  # One page per job. PostgreSQL serializes page insertion and its durable cursor.
  # A fixed upper time bound excludes new scrobbles while traversing history.
  class HistoricalImporter
    def initialize(run, client: Clients::Lastfm.new(username: run.source_username))
      @run, @client = run, client
    end

    def page!
      @run.with_lock do
        return if @run.completed? || @run.superseded?
        raw = @client.recent_tracks(page: @run.next_page, to: @run.upper_bound, limit: 200)
        parsed = RecentTracksParser.parse(raw)
        meta = parsed.fetch(:meta)
        raise Clients::InvalidResponse unless meta[:page] == @run.next_page && meta[:total_pages] && meta[:total]
        if @run.expected_count && @run.expected_count != meta[:total]
          raise Clients::InvalidResponse # Upstream history changed: explicit restart/replay required.
        end
        page = ImportPage.create!(import_run: @run, number: @run.next_page, raw_body: raw, checksum: Digest::SHA256.hexdigest(raw))
        rows = parsed.fetch(:tracks).filter_map do |track|
          next unless track[:played_at]
          fingerprint = Digest::SHA256.hexdigest(JSON.generate([ @run.source_username.downcase,
            track[:played_at].to_i, track[:artist_name], track[:album_name], track[:track_name] ]))
          # Preserve pre-milestone rows without manufacturing raw source provenance.
          legacy = @run.user.scrobbles.where(source_fingerprint: nil, played_at: track[:played_at])
          next if legacy.any? { |s| s.payload.is_a?(Hash) && %w[artist_name album_name track_name].all? { |k| s.payload[k] == track[k.to_sym] } }
          { user_id: @run.user_id, played_at: track[:played_at], payload: track,
            source_fingerprint: fingerprint, import_page_id: page.id, created_at: Time.current, updated_at: Time.current }
        end
        inserted = rows.empty? ? 0 : Scrobble.insert_all(rows, unique_by: [ :user_id, :source_fingerprint ]).rows.count
        complete = meta[:total_pages] == 0 || @run.next_page >= meta[:total_pages]
        @run.update!(status: complete ? :completed : :running, next_page: @run.next_page + 1,
          total_pages: meta[:total_pages], expected_count: meta[:total],
          scrobbles_processed: @run.scrobbles_processed.to_i + inserted, last_success_at: Time.current,
          last_error: nil, range_start_at: @run.user.scrobbles.minimum(:played_at), range_end_at: @run.user.scrobbles.maximum(:played_at))
      end
    rescue Clients::NetworkError, Clients::RateLimited
      @run.update!(last_error: "Last.fm is unavailable. Retrying with a bounded delay.")
      raise
    end
  end
end
