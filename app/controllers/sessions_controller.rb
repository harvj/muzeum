class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: %i[login callback]
  rate_limit to: 10, within: 3.minutes, only: :login,
    if: -> { !Current.session && login_navigation? }, with: :sign_in_rate_limited

  def login
    return head :no_content unless login_navigation?
    return redirect_to archive_path if Current.session

    response.headers["Referrer-Policy"] = "no-referrer"
    destination = params.key?(:resume) ? LoginDestination.from_handoff(params[:resume]) : archive_path
    unless destination
      return redirect_to root_path, alert: "This sign-in link expired or could not be verified. Please try again."
    end

    reset_session
    session[:oidc_auto_blocked] = true
    session[:oidc_return_to] = destination
    session[:oidc_browser] = SecureRandom.hex(32)
    OidcAttempt.where(expires_at: ...Time.current).delete_all
    attempt = OidcAttempt.create!(state: SecureRandom.hex(32), nonce: SecureRandom.hex(32),
      verifier: SecureRandom.urlsafe_base64(64), expires_at: 10.minutes.from_now,
      browser_digest: attempt_binding(destination))
    session[:oidc_attempt_state] = attempt.state
    redirect_to OidcClient.new.authorization_uri(attempt), allow_other_host: true
  rescue OidcClient::Failure
    attempt&.destroy!
    clear_attempt
    redirect_to root_path, alert: "Sign-in is temporarily unavailable. Please try again."
  end

  def callback
    response.headers["Referrer-Policy"] = "no-referrer"
    response_fields = callback_fields
    state = response_fields.fetch("state", []).sole
    raise OidcClient::Failure unless state.match?(/\A[0-9a-f]{64}\z/) && state == session[:oidc_attempt_state]

    destination = sign_in_destination
    attempt = OidcAttempt.consume!(state, attempt_binding(destination))
    clear_attempt
    codes = response_fields.fetch("code", [])
    raise OidcClient::Failure unless attempt && codes.one? && codes.first.present? && !response_fields.key?("error")

    subject, grant = OidcClient.new.exchange(codes.first, attempt)
    user = User.find_or_create_by!(oidc_issuer: OidcClient::ISSUER, oidc_subject: subject)
    raise OidcClient::Failure unless user.login_enabled?

    start_session(user, grant: grant)
    redirect_to destination, status: :see_other
  rescue OidcClient::Failure, Enumerable::SoleItemExpectedError, ArgumentError
    session[:oidc_auto_blocked] = true
    redirect_to root_path, alert: "Sign-in could not be verified. Please try again."
  end

  def destroy
    grant = Current.session&.grant_token
    terminate_session
    OidcClient.new.revoke(grant) if grant
    redirect_to root_path, status: :see_other
  rescue OidcClient::Failure
    redirect_to root_path, status: :see_other
  end

  private

  def login_navigation?
    interactive_login_request? &&
      request.headers["Sec-Fetch-Mode"].in?([ nil, "navigate" ]) &&
      request.headers["Sec-Fetch-Dest"].in?([ nil, "document" ])
  end

  def callback_fields
    raise OidcClient::Failure unless request.get? && request.query_string.bytesize <= 8_192

    URI.decode_www_form(request.query_string).each_with_object({}) do |(key, value), fields|
      raise OidcClient::Failure if key.match?(/\A(?:state|code|error)\[/)
      next unless key.in?(%w[state code error])

      (fields[key] ||= []) << value
    end
  end

  def sign_in_destination
    LoginDestination.validate(session[:oidc_return_to]) || archive_path
  end

  def attempt_binding(destination)
    Digest::SHA256.hexdigest([ session[:oidc_browser], OidcClient.callback_uri, destination ].to_json)
  end

  def clear_attempt
    session.delete(:oidc_attempt_state)
    session.delete(:oidc_browser)
  end

  def sign_in_rate_limited
    session[:oidc_auto_blocked] = true
    redirect_to root_path, alert: "Please try again later."
  end
end
