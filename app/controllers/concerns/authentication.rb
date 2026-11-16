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
  end

  def require_authentication
    redirect_to new_session_path unless Current.session
  end

  def prevent_private_caching
    response.headers["Cache-Control"] = "no-store"
  end

  def start_session(user)
    Current.session&.destroy!
    reset_session
    Current.session = user.sessions.create!(expires_at: 12.hours.from_now)
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
