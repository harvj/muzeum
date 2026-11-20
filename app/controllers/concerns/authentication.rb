module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :prevent_private_caching
    before_action :resume_session
    before_action :require_authentication
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
    session[:oidc_auto_blocked] = true
    Current.session = nil
  end

  def require_authentication
    return if Current.session

    destination = LoginDestination.validate(request.fullpath)
    if destination && interactive_login_request? && request.headers["Sec-Fetch-Mode"] == "navigate" &&
        request.headers["Sec-Fetch-Dest"] == "document" && !session[:oidc_auto_blocked]
      return redirect_to login_path(resume: LoginDestination.handoff(destination))
    end

    redirect_to root_path
  end

  def interactive_login_request?
    request.get? && request.format.html? && !request.xhr? && request.headers["Turbo-Frame"].blank? &&
      [ request.headers["Purpose"], request.headers["Sec-Purpose"] ].compact.none? { |value| value.match?(/prefetch|prerender/i) }
  end

  def prevent_private_caching
    response.headers["Cache-Control"] = "no-store"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
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
    session[:oidc_auto_blocked] = true
  end
end
