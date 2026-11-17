module Lastfm
  class HistoricalImporter
    LOCK_NAMESPACE = 1_294_083

    def initialize(run, client: Clients::Lastfm.new(username: run.source_username), authorize: true)
      @run, @client, @authorize = run, client, authorize
    end

    def page!
      account = @run.lastfm_account or raise AccountConflict
      ImportRun.connection_pool.with_connection do |connection|
        locked = connection.select_value("SELECT pg_try_advisory_lock(#{LOCK_NAMESPACE}, #{Integer(account.id)})")
        return false unless locked
        begin
          @run.reload
          return false if @run.completed? || @run.superseded? || @run.failed?
          return false if @run.retry_at && @run.retry_at > Time.current
          account.reload.authorize!(@run) if @authorize
          phase = @run.boundary_second && !@run.boundary_done ? "boundary" : "main"
          lower = phase == "boundary" ? @run.boundary_second : @run.lower_bound
          upper = phase == "boundary" ? @run.boundary_second : @run.upper_bound
          number = phase == "boundary" ? @run.boundary_page : @run.next_page
          # Inclusive desired intervals: overlap provider's documented 'after' lower bound.
          arguments = { page: number, to: upper + 1, limit: 200 }
          arguments[:from] = lower - 1 if lower
          requested_at = Time.current
          begin
            raw = ActiveSupport::Notifications.instrument("fetch.lastfm") { @client.recent_tracks(**arguments) }
          rescue Clients::NetworkError, Clients::RateLimited, Clients::Unauthorized, Clients::InvalidResponse => error
            SourceFetch.create!(import_run: @run, lastfm_account: account, page_number: number, lower_bound: lower,
              upper_bound: upper, phase: phase, request_parameters: arguments, requested_at: requested_at, outcome: error.raw_body ? "provider_error" : "transport_error",
              raw_body: error.raw_body, checksum: error.raw_body && Digest::SHA256.hexdigest(error.raw_body),
              error_class: error.class.name, retry_number: @run.retry_count)
            raise
          end
          # A fetched response survives a later parsing/transaction/database failure.
          fetch = SourceFetch.create!(import_run: @run, lastfm_account: account, page_number: number, lower_bound: lower,
            upper_bound: upper, phase: phase, request_parameters: arguments, requested_at: requested_at, outcome: "response", raw_body: raw,
            checksum: Digest::SHA256.hexdigest(raw), retry_number: @run.retry_count)
          begin
            source = ActiveSupport::Notifications.instrument("parse.lastfm") { SourcePage.new(raw) }
            raise SourceDrift unless source.meta["page"] == number
            raise SourceDrift if source.meta["user"] && !source.meta["user"].casecmp?(account.username)
            expected = phase == "boundary" ? @run.boundary_total : @run.expected_count
            raise SourceDrift if expected && expected != source.meta["total"]
            if source.meta["total"].positive? && (source.meta["totalPages"].zero? || source.items.empty?)
              raise SourceDrift
            end
            # Never call an API response outside the fixed interval a listening event.
            source.items.each do |item|
              time = item[:payload][:played_at]&.to_i
              item[:classification] ||= "outside_window" if time && (time > upper || (lower && time < lower))
            end
            writer = PageWriter.new(@run, fetch, source, authorize: @authorize)
            ActiveSupport::Notifications.instrument("commit.lastfm") { writer.commit! }
          rescue Clients::InvalidResponse => error
            IngestionIssue.create!(lastfm_account: account, import_run: @run, source_fetch: fetch,
              kind: error.is_a?(SourceDrift) ? "source_drift" : "malformed_response", details: { checkpoint_unchanged: true })
            raise
          end
          true
        ensure
          connection.execute("SELECT pg_advisory_unlock(#{LOCK_NAMESPACE}, #{Integer(account.id)})")
        end
      end
    end
  end
end
