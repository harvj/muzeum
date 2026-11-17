class SyncAccountJob < ApplicationJob
  queue_as :imports
  def perform(account_id)
    return unless ENV["LASTFM_SYNC_ENABLED"] == "1"
    account = LastfmAccount.find(account_id)
    return unless account.sync_enabled && account.state == "active" && account.next_poll_at <= Time.current
    run = Lastfm::Scheduler.run_for!(account)
    Lastfm::HistoricalImporter.new(run).page! if run
  rescue Lastfm::Deferred => error
    account&.update!(dispatch_until: Time.current + error.wait)
  rescue Clients::NetworkError, Clients::RateLimited, Clients::InvalidResponse, Clients::Unauthorized, Lastfm::PermissionDenied, ActiveRecord::ActiveRecordError => error
    raise if error.is_a?(ActiveRecord::ActiveRecordError) && !run
    Lastfm::Scheduler.failure!(run, error) if run
    account&.update!(dispatch_until: nil, state: "paused", last_error: "No active source import authorization.") if !run && error.is_a?(Lastfm::PermissionDenied)
  end
end
