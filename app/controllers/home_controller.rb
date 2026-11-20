class HomeController < ApplicationController
  def show
    load_dashboard(before: params[:before])
  end

  def updates
    @account = current_user.source_account
    return head :no_content if @account && params[:version] == @account.updated_at.iso8601(6)
    load_dashboard
    render turbo_stream: turbo_stream.replace("archive_dashboard", partial: "home/dashboard")
  end

  def summary
    @account = current_user.source_account
    observations = archive_observations
    @count = observations.count
    @earliest = observations.minimum(:played_at)
    @latest = observations.maximum(:played_at)
    @artists = observations.distinct.count(Arel.sql("NULLIF(payload->>'artist_name', '')"))
    @albums = observations.where("NULLIF(payload->>'album_name', '') IS NOT NULL").distinct.count(Arel.sql("jsonb_build_array(payload->>'artist_name', payload->>'album_name')"))
    @tracks = observations.where("NULLIF(payload->>'track_name', '') IS NOT NULL").distinct.count(Arel.sql("jsonb_build_array(payload->>'artist_name', payload->>'track_name')"))
  end

  private

  def archive_observations
    return Scrobble.none unless @account

    # Check the grant once so PostgreSQL can seek directly in this account's chronological index.
    grant = current_user.user_lastfm_accounts.active.where(lastfm_account_id: @account.id)
    Scrobble.where(lastfm_account_id: @account.id).where(grant.arel.exists)
  end

  def load_dashboard(before: nil)
    @account ||= current_user.source_account
    @recent, @next_page = ListeningPage.fetch(archive_observations, before:)
    @first_page = before.blank?
    @recent_recordings, @recent_releases = ListeningPage.catalog(@recent, RecordingResolution::Ledger.effective(current_user))
    @can_manage_account = @account && current_user.managed_archive_grants.exists?(lastfm_account_id: @account.id)
    @ownership = ListeningProfile.find_by(lastfm_account: @account, owner: current_user) if @account
    @run = @account&.import_runs&.order(created_at: :desc)&.first if @can_manage_account
  end
end
