class HomeController < ApplicationController
  def show
    load_dashboard
  end

  def updates
    @account = current_user.source_account
    return head :no_content if @account && params[:version] == @account.updated_at.iso8601(6)
    load_dashboard
    render turbo_stream: turbo_stream.replace("archive_dashboard", partial: "home/dashboard")
  end

  private

  def load_dashboard
    @account ||= current_user.source_account
    observations = @account ? current_user.archive_observations.where(lastfm_account: @account) : Scrobble.none
    @recent = observations.order(played_at: :desc, id: :desc).limit(50).select(:id, :played_at, :payload).to_a
    @count = observations.count
    @earliest = observations.minimum(:played_at)
    @latest = observations.maximum(:played_at)
    @artists = observations.distinct.count(Arel.sql("NULLIF(payload->>'artist_name', '')"))
    @albums = observations.where("NULLIF(payload->>'album_name', '') IS NOT NULL").distinct.count(Arel.sql("jsonb_build_array(payload->>'artist_name', payload->>'album_name')"))
    @tracks = observations.where("NULLIF(payload->>'track_name', '') IS NOT NULL").distinct.count(Arel.sql("jsonb_build_array(payload->>'artist_name', payload->>'track_name')"))
    @run = @account&.import_runs&.order(created_at: :desc)&.first
  end
end
