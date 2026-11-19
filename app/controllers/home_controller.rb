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
    load_recent_catalog
    @count = observations.count
    @earliest = observations.minimum(:played_at)
    @latest = observations.maximum(:played_at)
    @artists = observations.distinct.count(Arel.sql("NULLIF(payload->>'artist_name', '')"))
    @albums = observations.where("NULLIF(payload->>'album_name', '') IS NOT NULL").distinct.count(Arel.sql("jsonb_build_array(payload->>'artist_name', payload->>'album_name')"))
    @tracks = observations.where("NULLIF(payload->>'track_name', '') IS NOT NULL").distinct.count(Arel.sql("jsonb_build_array(payload->>'artist_name', payload->>'track_name')"))
    @run = @account&.import_runs&.order(created_at: :desc)&.first
  end

  def load_recent_catalog
    effective_ids = RecordingResolution::Ledger.effective(current_user)
      .where(scrobbles: { id: @recent.map(&:id) })
      .where.not("effective_resolution.recording_id" => nil)
      .pluck("scrobbles.id", Arel.sql("effective_resolution.recording_id")).to_h
    recordings = Recording.where(id: effective_ids.values).eager_load(recording_artists: :artist).index_by(&:id)
    @recent_recordings = effective_ids.transform_values { |id| recordings[id] }

    releases = Release.joins(:catalog_track_slots)
      .where(catalog_track_slots: { recording_id: recordings.keys }, title: @recent.filter_map { |play| play.payload["album_name"].presence })
      .where.not(catalog_verified_at: nil)
      .select("releases.*", "catalog_track_slots.recording_id AS member_recording_id").distinct
      .group_by(&:member_recording_id)
    @recent_releases = @recent.each_with_object({}) do |play, matches|
      candidates = releases.fetch(effective_ids[play.id], []).select { |release| release.title == play.payload["album_name"] }
      if (edition = play.payload["album_mbid"].presence)
        candidates.select! { |release| release.ingested_from_release_mbid == edition }
      end
      matches[play.id] = candidates.first if candidates.one?
    end
  end
end
