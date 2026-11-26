class PublicProfilesController < ApplicationController
  skip_before_action :require_authentication
  include PublishedProfile

  def show
    @recent, @next_page = ListeningPage.fetch(@profile_catalog.observations, before: params[:before])
    @recent_recordings, @recent_releases = ListeningPage.catalog(@recent, @profile_catalog.effective)
    @release_selection = ReleaseConfigurationSelection.new(@public_profile.owner, @recent_releases.values.flatten.map(&:id).uniq)
  end
end
