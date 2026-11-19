class PublicProfilesController < ApplicationController
  skip_before_action :resume_session, :require_authentication
  include PublishedProfile

  def show
    @recent = ListeningPage.chronological(@profile_catalog.observations, before: params[:before])
      .limit(ListeningPage::SIZE + 1).select(:id, :played_at, :payload).to_a
    @next_page = @recent.pop && @recent.last.id if @recent.size > ListeningPage::SIZE
    @recent_recordings, @recent_releases = ListeningPage.catalog(@recent, @profile_catalog.effective)
  end
end
