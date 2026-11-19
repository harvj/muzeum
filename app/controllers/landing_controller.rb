class LandingController < ApplicationController
  skip_before_action :resume_session, :require_authentication

  def show
    @featured_profile = ListeningProfile.published.includes(:lastfm_account).find_by(lastfm_accounts: { lookup_key: "qalephd" })
  end
end
