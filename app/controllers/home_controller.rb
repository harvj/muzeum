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
    @count, @earliest, @latest, @artists, @albums, @tracks = archive_statistics
  end

  private

  def archive_statistics
    observations = archive_observations
    latest_id = observations.order(id: :desc).pick(:id)
    return [ 0, nil, nil, 0, 0, 0 ] unless latest_id

    # Source rows are immutable and PageWriter appends under the archive account lock.
    # A new observation advances the key; a resolution decision cannot affect these counts.
    Rails.cache.fetch([ "archive-source-summary-v1", @account.id, latest_id ], expires_in: 1.day) do
      source = Scrobble.where(lastfm_account_id: @account.id, id: ..latest_id)
      groups = source.select(<<~SQL).group(Arel.sql("GROUPING SETS ((), (artist), (artist, album), (artist, track))"))
        payload->>'artist_name' AS artist, payload->>'album_name' AS album, payload->>'track_name' AS track,
        GROUPING(payload->>'artist_name', payload->>'album_name', payload->>'track_name') AS level,
        COUNT(*) AS plays, MIN(played_at) AS earliest, MAX(played_at) AS latest
      SQL
      Scrobble.from(groups, :source_groups).pick(
        Arel.sql("MAX(plays) FILTER (WHERE level = 7)"),
        Arel.sql("MAX(earliest) FILTER (WHERE level = 7)"),
        Arel.sql("MAX(latest) FILTER (WHERE level = 7)"),
        Arel.sql("COUNT(*) FILTER (WHERE level = 3 AND NULLIF(artist, '') IS NOT NULL)"),
        Arel.sql("COUNT(*) FILTER (WHERE level = 1 AND NULLIF(album, '') IS NOT NULL)"),
        Arel.sql("COUNT(*) FILTER (WHERE level = 2 AND NULLIF(track, '') IS NOT NULL)")
      )
    end
  end

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
