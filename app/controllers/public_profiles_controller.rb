class PublicProfilesController < ApplicationController
  skip_before_action :require_authentication
  include PublishedProfile

  def show
    @recent, @next_page = ListeningPage.fetch(@profile_catalog.observations, before: params[:before])
    @recent_recordings, @recent_releases = ListeningPage.catalog(@recent, @profile_catalog.effective)
  end
end
