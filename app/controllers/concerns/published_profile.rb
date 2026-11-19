module PublishedProfile
  extend ActiveSupport::Concern

  included do
    before_action :load_published_profile, if: :public_profile_request?
  end

  private

  def public_profile_request?
    request.path_parameters[:profile].present?
  end

  def load_published_profile
    @public_profile = ListeningProfile.published.includes(:lastfm_account, :owner)
      .find_by!(lastfm_accounts: { lookup_key: request.path_parameters.fetch(:profile) })
    @profile_catalog = PublicProfileCatalog.new(@public_profile)
  end
end
