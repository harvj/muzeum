class HistoricalImportJob < ApplicationJob
  queue_as :imports
  limits_concurrency to: 1, key: ->(run_id) { ImportRun.find(run_id).lastfm_account_id }, duration: 5.minutes

  def perform(run_id)
    run = ImportRun.find(run_id)
    return if run.completed? || run.superseded? || run.failed?
    run.lastfm_account.authorize!(run)
    worked = Lastfm::HistoricalImporter.new(run).page!
    self.class.set(wait: Lastfm::RequestBudget.interval).perform_later(run_id) if worked && run.reload.running?
  rescue Lastfm::Deferred => error
    self.class.set(wait: error.wait).perform_later(run_id)
  rescue Clients::NetworkError, Clients::RateLimited, Clients::InvalidResponse, Clients::Unauthorized, Lastfm::PermissionDenied, ActiveRecord::ActiveRecordError => error
    raise unless run
    Lastfm::Scheduler.failure!(run, error)
    if run.retry_count < 5 && !run.failed? && !error.is_a?(Lastfm::SourceDrift)
      self.class.set(wait_until: run.retry_at).perform_later(run_id)
    end
  end
end
