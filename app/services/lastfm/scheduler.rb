module Lastfm
  class Scheduler
    LOOKBACK = 48.hours.to_i
    WINDOW = 7.days.to_i

    def self.dispatch!(now: Time.current, limit: [ (1 / RequestBudget.interval).ceil, 20 ].min)
      return 0 unless ENV["LASTFM_SYNC_ENABLED"] == "1"
      ids = []
      LastfmAccount.transaction do
        accounts = LastfmAccount.active.where(sync_enabled: true).where("next_poll_at <= ? AND (dispatch_until IS NULL OR dispatch_until <= ?)", now, now)
          .order(:next_poll_at, :id).limit(limit).lock("FOR UPDATE SKIP LOCKED")
        accounts.each do |account|
          account.update!(dispatch_until: now + 30.seconds)
          ids << account.id
        end
      end
      # Queue and primary databases are independent. A missing enqueue is recovered
      # from the 30-second dispatch lease; durable source/run state is authoritative.
      ids.each_with_index { |id, index| SyncAccountJob.set(wait: index * RequestBudget.interval).perform_later(id) }
      ids.size
    end

    def self.run_for!(account)
      account.with_lock do
        account.authorize!
        run = account.import_runs.where(status: %i[pending running paused]).order(:id).last
        if run
          return nil if run.retry_at && run.retry_at > Time.current
          if run.failure_kind == "source_drift"
            generation = run.authorization_context.fetch("drift_generation", 0)
            if run.kind == "incremental" && generation < 3
              run.update!(status: :superseded)
              return account.import_runs.create!(user: account.archive_user, source_username: run.source_username,
                lower_bound: run.lower_bound, upper_bound: run.upper_bound, kind: "incremental", actor_kind: "scheduler",
                authorization_context: { service: "lastfm-scheduler-v1", replay_of_run_id: run.id, drift_generation: generation + 1 })
            end
            account.update!(state: "paused", last_error: "Repeated source drift requires reviewed replay of the recorded interval.")
            return nil
          end
          run.update!(status: :pending) if run.paused?
          return run
        end
        previous = account.import_runs.where(status: :failed, failure_kind: "Lastfm::PermissionDenied").order(:id).last
        if previous
          cursor = previous.attributes.slice("source_username", "lower_bound", "upper_bound", "next_page", "total_pages", "expected_count", "boundary_second", "boundary_page", "boundary_total", "boundary_done", "kind")
          return account.import_runs.create!(cursor.merge(user: account.archive_user, actor_kind: "scheduler",
            authorization_context: { service: "lastfm-scheduler-v1", continued_from_run_id: previous.id }))
        end
        through = account.synced_through
        upper = Time.current.to_i - 5
        lower = through ? [ through - LOOKBACK, 1 ].max : nil
        upper = [ upper, lower + WINDOW ].min if lower
        account.import_runs.create!(user: account.archive_user, source_username: account.username,
          lower_bound: lower, upper_bound: upper, kind: through ? "incremental" : "historical",
          actor_kind: "scheduler", authorization_context: { service: "lastfm-scheduler-v1", policy: "active-import-membership-v1" })
      end
    end

    def self.failure!(run, error)
      account = run.lastfm_account
      account.with_lock do
        run.reload
        attempts = run.retry_count + 1
        delay = [ 30 * 2**[ attempts - 1, 9 ].min, 21_600 ].min + account.id % 11
        delay = [ delay, 900 ].max if attempts >= 5
        retry_after = error.respond_to?(:retry_after) ? error.retry_after : nil
        delay = [ delay, retry_after.to_i, 1 ].max
        permanent = error.is_a?(Clients::Unauthorized) || error.is_a?(PermissionDenied)
        kind = error.is_a?(SourceDrift) ? "source_drift" : error.class.name
        remaining_grants = account.authorized_memberships.exists?
        drift_exhausted = error.is_a?(SourceDrift) && (run.kind != "incremental" || run.authorization_context.fetch("drift_generation", 0) >= 3)
        message = permanent ? "Source import permission or provider access is unavailable." : "Source synchronization paused; retry and source evidence retained."
        run.update!(status: permanent ? :failed : :paused, retry_count: attempts, retry_at: Time.current + delay,
          failure_kind: kind, last_error: message)
        account.update!(failure_count: account.failure_count + 1, next_poll_at: Time.current + (error.is_a?(PermissionDenied) && remaining_grants ? 0 : delay),
          dispatch_until: nil, last_error: message, state: (permanent && !remaining_grants) || error.is_a?(Clients::Unauthorized) || drift_exhausted ? "paused" : account.state)
        IngestionIssue.create!(lastfm_account: account, import_run: run, kind: "retry",
          details: { error_class: kind, attempt: attempts, retry_at: run.retry_at, retry_after_seconds: retry_after, permanent: permanent })
      end
    end
  end
end
