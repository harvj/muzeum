class ApplicationShellController < ApplicationController
  skip_before_action :require_authentication

  def show
    return head :unauthorized unless Current.session

    evidence = OidcClient.new.shell_evidence(Current.session.grant_token, subject: current_user.oidc_subject)
    return head :no_content unless evidence

    render json: { username: evidence.fetch(:username), expires_at: evidence.fetch(:expires_at),
      destinations: ApplicationShellRegistry.destinations(evidence.fetch(:destinations)) }
  rescue OidcClient::Failure
    head :no_content
  end
end
