class ApplicationShellController < ApplicationController
  skip_before_action :require_authentication

  def show
    return head :service_unavailable if @session_verification_unavailable

    local_session = Current.session
    binding = request.headers["X-Muzeum-Shell-Session"].to_s
    return head :unauthorized unless local_session && ActiveSupport::SecurityUtils.secure_compare(
      binding, ApplicationShellEvidence.session_binding(local_session)
    )

    evidence = OidcClient.new.shell_evidence(local_session)
    active_session = Session.unexpired.find_by(id: local_session.id)
    return head :unauthorized unless active_session&.grant_token == local_session.grant_token &&
      active_session.user_id == local_session.user_id

    valid_for = evidence.fetch(:expires_at) - Time.current.to_i
    return head :service_unavailable unless valid_for.positive?

    applications = ApplicationShellRegistry.entries.select do |entry|
      entry["availability"] == "production" && entry["id"] != "muzeum" && evidence.fetch(:ids).include?(entry["id"])
    end
    username = remember_session_username(evidence.fetch(:username))
    render json: { username: username, valid_for: valid_for, applications: applications }
  rescue OidcClient::Failure
    head :service_unavailable
  end
end
