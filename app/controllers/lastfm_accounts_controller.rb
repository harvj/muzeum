class LastfmAccountsController < ApplicationController
  def update
    username = params[:lastfm_username].to_s.strip
    unless username.match?(/\A[a-zA-Z0-9_-]{1,64}\z/)
      redirect_to root_path, alert: "Enter a valid public Last.fm username."
      return
    end
    validated = Clients::Lastfm.new(username: username).public_username!
    raise Lastfm::AccountConflict unless username.casecmp?(validated)
    current_user.with_lock do
      if current_user.lastfm_username.present? && !current_user.lastfm_username.casecmp?(validated)
        redirect_to root_path, alert: "Changing an archived account requires operator reconciliation."
        return
      end
      account = LastfmAccount.associate!(current_user, validated)
      current_user.update!(lastfm_username: validated)
      account.update!(sync_enabled: true)
    end
    redirect_to root_path, notice: "Public Last.fm account associated. This does not verify ownership."
  rescue Clients::InvalidResponse
    redirect_to root_path, alert: "Last.fm could not validate that username. Check it and try again."
  rescue Clients::NetworkError, Clients::RateLimited, Clients::Unauthorized, Lastfm::Deferred, KeyError
    redirect_to root_path, alert: "Last.fm is unavailable. Your association has not changed."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, Lastfm::AccountConflict
    redirect_to root_path, alert: "That account is already associated. Contact the operator."
  end
end
