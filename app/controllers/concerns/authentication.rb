module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :resume_session
    before_action :require_authentication
    before_action :prevent_private_caching
    helper_method :current_user
  end

  private

  def current_user
    Current.user
  end

  def resume_session
    Current.session = Session.unexpired.includes(:user).find_by(id: cookies.signed[:session_id])
    Current.session = nil unless Current.user&.login_enabled?
    return unless Current.session
    if Current.session.last_seen_at.nil? || Current.session.last_seen_at < 12.hours.ago
      Current.session = nil
      return
    end
    if action_name != "destroy" && (Current.session.verified_at.nil? || Current.session.verified_at < 60.seconds.ago)
      unless OidcClient.new.active?(Current.session.grant_token, subject: Current.user.oidc_subject)
        terminate_session
        return
      end
      Current.session.update!(verified_at: Time.current)
    end
    Current.session.update!(last_seen_at: Time.current) if request.get? && request.format.html?
  rescue OidcClient::Failure
    Current.session = nil
  end

  def require_authentication
    redirect_to new_session_path unless Current.session
  end

  def prevent_private_caching
    response.headers["Cache-Control"] = "no-store"
    response.headers["Referrer-Policy"] = "no-referrer"
  end

  def start_session(user, grant:)
    Current.session&.destroy!
    reset_session
    Current.session = user.sessions.create!(expires_at: 7.days.from_now, last_seen_at: Time.current, verified_at: Time.current, grant_token: grant)
    cookies.signed[:session_id] = { value: Current.session.id, httponly: true,
      secure: Rails.env.production?, same_site: :lax, expires: Current.session.expires_at }
  end

  def terminate_session
    Current.session&.destroy!
    Current.session = nil
    cookies.delete(:session_id)
    reset_session
  end
end
