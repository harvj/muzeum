class ImportsController < ApplicationController
  def create
    current_user.with_lock do
      raise ActiveRecord::RecordNotFound if current_user.lastfm_username.blank?
      run = current_user.import_runs.where(status: %i[pending running failed]).order(:created_at).last
      if run && params[:restart] == "1"
        run.update!(status: :superseded)
        run = nil
      end
      if run
        run.update!(status: :pending, last_error: nil)
      else
        run = current_user.import_runs.create!(source_username: current_user.lastfm_username,
          upper_bound: Time.current.to_i, status: :pending, scrobbles_processed: 0)
      end
      HistoricalImportJob.perform_later(run.id)
    end
    redirect_to root_path, notice: "Import queued. You can leave this page; progress is saved on the server."
  end
end
