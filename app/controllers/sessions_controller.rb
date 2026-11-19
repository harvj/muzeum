class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: %i[new create callback]
  rate_limit to: 10, within: 3.minutes, only: %i[new create],
    if: -> { action_name == "create" || session[:oidc_auto_start] },
    with: :sign_in_rate_limited

  def new
    initiate_sign_in if session.delete(:oidc_auto_start)
  end

  def create
    initiate_sign_in
  end

  def callback
    response.headers["Referrer-Policy"] = "no-referrer"
    attempt = OidcAttempt.consume!(params[:state].to_s, session.delete(:oidc_browser))
    raise OidcClient::Failure unless attempt && params[:code].present? && params[:error].blank?
    subject, grant = OidcClient.new.exchange(params[:code], attempt)
    user = User.find_or_create_by!(oidc_issuer: OidcClient::ISSUER, oidc_subject: subject)
    raise OidcClient::Failure unless user.login_enabled?
    destination = sign_in_destination
    start_session(user, grant: grant)
    redirect_to destination, status: :see_other
  rescue StandardError, OpenIDConnect::ResponseObject::IdToken::InvalidToken
    session[:oidc_auto_blocked] = true
    session.delete(:oidc_auto_start)
    redirect_to new_session_path, alert: "Sign-in could not be verified. Please try again."
  end

  def destroy
    grant = Current.session&.grant_token
    terminate_session
    OidcClient.new.revoke(grant) if grant
    redirect_to new_session_path, status: :see_other
  rescue OidcClient::Failure
    redirect_to new_session_path, status: :see_other
  end

  private

  # Both automatic entry and the explicit CSRF-protected POST use this flow.
  def initiate_sign_in
    destination = sign_in_destination
    reset_session
    session[:oidc_auto_blocked] = true
    session[:oidc_return_to] = destination
    session[:oidc_browser] = SecureRandom.hex(32)
    OidcAttempt.where(expires_at: ...Time.current).delete_all
    attempt = OidcAttempt.create!(state: SecureRandom.hex(32), nonce: SecureRandom.hex(32),
      verifier: SecureRandom.urlsafe_base64(64), expires_at: 10.minutes.from_now,
      browser_digest: Digest::SHA256.hexdigest(session[:oidc_browser]))
    redirect_to OidcClient.new.authorization_uri(attempt), allow_other_host: true
  rescue StandardError
    redirect_to new_session_path, alert: "Sign-in is temporarily unavailable. Please try again."
  end

  def sign_in_destination
    value = session[:oidc_return_to]
    # The dashboard is currently the only interactive protected GET destination.
    value.is_a?(String) && value.match?(/\A\/archive(?:\?[^\r\n]*)?\z/) ? value : archive_path
  end

  def sign_in_rate_limited
    session.delete(:oidc_auto_start)
    session[:oidc_auto_blocked] = true
    redirect_to new_session_path, alert: "Please try again later."
  end
end
