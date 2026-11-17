class ImportsController < ApplicationController
  def create
    account = current_user.source_account or raise ActiveRecord::RecordNotFound
    account.with_lock do
      account.authorize!
      grant = current_user.user_lastfm_accounts.active.find_by!(lastfm_account: account, import_allowed: true)
      run = account.import_runs.where(status: %i[pending running paused failed]).order(:created_at).last
      restart_bounds = nil
      if run && params[:restart] == "1"
        restart_bounds = run.attributes.slice("lower_bound", "upper_bound", "kind")
        run.update!(status: :superseded)
        run = nil
      end
      if run
        raise Lastfm::PermissionDenied if run.actor_kind == "user" && run.user_id != current_user.id
        run.update!(status: :pending, retry_at: nil, retry_count: 0, last_error: nil, failure_kind: nil)
      else
        lower = account.synced_through && [ account.synced_through - Lastfm::Scheduler::LOOKBACK, 1 ].max
        upper = Time.current.to_i - 5
        upper = [ upper, lower + Lastfm::Scheduler::WINDOW ].min if lower
        bounds = restart_bounds || { lower_bound: lower, upper_bound: upper, kind: lower ? "incremental" : "historical" }
        run = account.import_runs.create!(bounds.merge(user: current_user, source_username: account.username, actor_kind: "user",
          authorization_context: { membership_id: grant.id, permission: "import", ownership_verified: false }))
      end
      HistoricalImportJob.perform_later(run.id)
    end
    redirect_to root_path, notice: "Import queued. Progress is saved independently of this page."
  rescue Lastfm::PermissionDenied
    redirect_to root_path, alert: "An active source import grant is required."
  end
end
