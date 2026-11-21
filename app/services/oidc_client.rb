require "openid_connect"

# Auth owns authentication/admission; no Auth database or email-based linking.
class OidcClient
  ISSUER = "https://auth.harvj.com".freeze
  class Failure < StandardError; end

  def self.configured?
    ENV["OIDC_CLIENT_ID"].present? && ENV["OIDC_CLIENT_SECRET"].present?
  end

  def self.callback_uri
    ENV.fetch("OIDC_REDIRECT_URI", "https://muzeum.fm/oidc/callback")
  end

  def initialize
    raise Failure unless self.class.configured?
  end

  def authorization_uri(attempt)
    client.authorization_uri(scope: %w[openid offline_access], response_type: :code,
      state: attempt.state, nonce: attempt.nonce, prompt: :consent,
      code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(attempt.verifier), padding: false),
      code_challenge_method: "S256")

  rescue OpenIDConnect::Exception, Faraday::Error, URI::InvalidURIError
    raise Failure
  end

  def exchange(code, attempt)
    client.authorization_code = code
    token = client.access_token!(code_verifier: attempt.verifier)
    claims = JSON::JWT.decode(token.id_token, :skip_verification)
    raise Failure unless claims.algorithm.to_s == "RS256"
    identity = OpenIDConnect::ResponseObject::IdToken.decode(token.id_token, discovery)
    identity.verify!(issuer: ISSUER, client_id: ENV.fetch("OIDC_CLIENT_ID"), nonce: attempt.nonce)
    raise Failure if identity.sub.blank? || identity.iat.to_i > Time.current.to_i + 30
    raise Failure if identity.azp.present? && identity.azp != ENV.fetch("OIDC_CLIENT_ID")
    raise Failure if Array(identity.aud).size > 1 && identity.azp != ENV.fetch("OIDC_CLIENT_ID")
    required_acr = ENV["OIDC_REQUIRED_ACR"].presence
    raise Failure if required_acr && identity.acr != required_acr
    raise Failure if token.refresh_token.blank?
    [ identity.sub, token.refresh_token, claims["preferred_username"] ]
  rescue OpenIDConnect::Exception, Rack::OAuth2::Client::Error, JSON::JWT::Exception, Faraday::Error, URI::InvalidURIError
    raise Failure
  end

  def active?(grant, subject:)
    response = http.post("#{ISSUER}/introspect", form: { token: grant, token_type_hint: "refresh_token" })
    raise Failure unless response.status.success?
    data = JSON.parse(response.to_s)
    # Rodauth opaque refresh-token introspection returns client_id but no sub.
    # The encrypted grant was bound to the verified subject at code exchange.
    data.fetch("active") == true && data["client_id"] == ENV.fetch("OIDC_CLIENT_ID") &&
      (!data.key?("sub") || data["sub"] == subject)
  rescue HTTP::Error, JSON::ParserError, KeyError
    raise Failure
  end

  def shell_evidence(local_session)
    metadata = HTTP.timeout(3).get("#{ISSUER}/.well-known/oauth-authorization-server")
    raise Failure unless metadata.status.success?

    data = JSON.parse(metadata.to_s)
    endpoint = URI(data.fetch("introspection_endpoint"))
    methods = data["introspection_endpoint_auth_methods_supported"]
    unless data["issuer"] == ISSUER && methods.is_a?(Array) && methods.include?("client_secret_basic") && endpoint.scheme == "https" && endpoint.host == URI(ISSUER).host &&
        endpoint.port == 443 && endpoint.userinfo.nil? && endpoint.query.nil? && endpoint.fragment.nil?
      raise Failure
    end

    response = http.post(endpoint.to_s, form: { token: local_session.grant_token, token_type_hint: "refresh_token",
      application_shell_version: "1" })
    raise Failure unless response.status.success? && response.headers["Cache-Control"].to_s.split(",").map { |directive| directive.strip.downcase }.include?("no-store")

    ApplicationShellEvidence.verify(JSON.parse(response.to_s), session: local_session, client_id: ENV.fetch("OIDC_CLIENT_ID"))
  rescue HTTP::Error, JSON::ParserError, KeyError, TypeError, URI::InvalidURIError, ArgumentError, ApplicationShellEvidence::Invalid
    raise Failure
  end

  def revoke(grant)
    http.headers("Accept" => "application/json").post("#{ISSUER}/revoke", json: { token: grant, token_type_hint: "refresh_token" })
  rescue HTTP::Error
    nil # Local logout is always available during provider outages.
  end

  private

  def discovery
    @discovery ||= OpenIDConnect::Discovery::Provider::Config.discover!(ISSUER).tap do |config|
      raise Failure unless config.issuer == ISSUER
      [ config.authorization_endpoint, config.token_endpoint, config.jwks_uri ].each do |endpoint|
        raise Failure unless URI(endpoint).scheme == "https" && URI(endpoint).host == "auth.harvj.com" && URI(endpoint).port == 443
      end
    end
  end

  def client
    @client ||= OpenIDConnect::Client.new(identifier: ENV.fetch("OIDC_CLIENT_ID"),
      secret: ENV.fetch("OIDC_CLIENT_SECRET"), redirect_uri: self.class.callback_uri,
      authorization_endpoint: discovery.authorization_endpoint, token_endpoint: discovery.token_endpoint)
  end

  def http
    HTTP.timeout(connect: 3, read: 5, write: 3).basic_auth(user: ENV.fetch("OIDC_CLIENT_ID"), pass: ENV.fetch("OIDC_CLIENT_SECRET"))
  end
end
