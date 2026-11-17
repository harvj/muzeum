class HistoricalImportJob < ApplicationJob
  queue_as :imports
  limits_concurrency to: 1, key: ->(run_id) { ImportRun.find(run_id).user_id }, duration: 5.minutes
  retry_on Clients::NetworkError, Clients::RateLimited, wait: :polynomially_longer, attempts: 5 do |job, error|
    run = ImportRun.find(job.arguments.first)
    run.update!(status: :failed, last_error: "Last.fm could not be reached after five attempts. Resume to try again.")
  end

  def perform(run_id)
    run = ImportRun.find(run_id)
    return if run.completed? || run.superseded? || !run.user.login_enabled?
    return unless run.source_username == run.user.lastfm_username
    Lastfm::HistoricalImporter.new(run).page!
    self.class.set(wait: 1.second).perform_later(run_id) unless run.reload.completed?
  rescue Clients::InvalidResponse, Clients::Unauthorized
    run&.update!(status: :failed, last_error: "Last.fm returned an invalid response. Resume to try again.")
  end
end
