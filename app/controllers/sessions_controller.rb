class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: %i[new create callback]
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_session_path, alert: "Please try again later." }

  def new
  end

  def create
    reset_session
    session[:oidc_browser] = SecureRandom.hex(32)
    OidcAttempt.where(expires_at: ...Time.current).delete_all
    attempt = OidcAttempt.create!(state: SecureRandom.hex(32), nonce: SecureRandom.hex(32),
      verifier: SecureRandom.urlsafe_base64(64), expires_at: 10.minutes.from_now,
      browser_digest: Digest::SHA256.hexdigest(session[:oidc_browser]))
    redirect_to OidcClient.new.authorization_uri(attempt), allow_other_host: true
  rescue StandardError
    redirect_to new_session_path, alert: "Sign-in is temporarily unavailable. Please try again."
  end

  def callback
    response.headers["Referrer-Policy"] = "no-referrer"
    attempt = OidcAttempt.consume!(params[:state].to_s, session.delete(:oidc_browser))
    raise OidcClient::Failure unless attempt && params[:code].present? && params[:error].blank?
    subject, grant = OidcClient.new.exchange(params[:code], attempt)
    user = User.find_or_create_by!(oidc_issuer: OidcClient::ISSUER, oidc_subject: subject)
    raise OidcClient::Failure unless user.login_enabled?
    start_session(user, grant: grant)
    redirect_to root_path, status: :see_other
  rescue StandardError, OpenIDConnect::ResponseObject::IdToken::InvalidToken
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
end
