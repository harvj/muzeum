class HomeController < ApplicationController
  def show
    observations = current_user.scrobbles
    @count = observations.count
    @earliest = observations.minimum(:played_at)
    @latest = observations.maximum(:played_at)
    @artists = observations.distinct.count(Arel.sql("NULLIF(payload->>'artist_name', '')"))
    @albums = observations.where("NULLIF(payload->>'album_name', '') IS NOT NULL").distinct.count(Arel.sql("jsonb_build_array(payload->>'artist_name', payload->>'album_name')"))
    @tracks = observations.where("NULLIF(payload->>'track_name', '') IS NOT NULL").distinct.count(Arel.sql("jsonb_build_array(payload->>'artist_name', payload->>'track_name')"))
    @run = current_user.import_runs.order(created_at: :desc).first
  end
end
