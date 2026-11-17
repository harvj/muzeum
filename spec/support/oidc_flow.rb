module OidcFlow
  def prepare_oidc
    @old_env = ENV.to_h.slice("OIDC_CLIENT_ID", "OIDC_CLIENT_SECRET", "OIDC_REDIRECT_URI")
    ENV["OIDC_CLIENT_ID"] = "muzeum-test"
    ENV["OIDC_CLIENT_SECRET"] = "test-only-secret"
    ENV["OIDC_REDIRECT_URI"] = "http://www.example.com/oidc/callback"
    @signing_key = OpenSSL::PKey::RSA.generate(2048)
    @subject = "existing-auth-uuid"
    metadata = { issuer: OidcClient::ISSUER, authorization_endpoint: "https://auth.harvj.com/authorize",
      token_endpoint: "https://auth.harvj.com/token", jwks_uri: "https://auth.harvj.com/jwks",
      response_types_supported: [ "code" ], subject_types_supported: [ "public" ], id_token_signing_alg_values_supported: [ "RS256" ] }
    stub_request(:get, "https://auth.harvj.com/.well-known/openid-configuration").to_return(headers: { "Content-Type" => "application/json" }, body: metadata.to_json)
    stub_request(:get, "https://auth.harvj.com/jwks").to_return(headers: { "Content-Type" => "application/json" }, body: { keys: [ JSON::JWK.new(@signing_key.public_key, kid: "test") ] }.to_json)
    stub_request(:post, "https://auth.harvj.com/revoke").to_return(status: 200)
  end

  def finish_oidc(claims: {}, key: @signing_key)
    post session_path
    expect(response).to have_http_status(:redirect)
    query = Rack::Utils.parse_query(URI(response.location).query)
    expect(query["code_challenge_method"]).to eq("S256")
    expect(query["scope"]).to eq("openid offline_access")
    attempt = OidcAttempt.find_by!(state: query["state"])
    expect(query["code_challenge"]).to eq(Base64.urlsafe_encode64(Digest::SHA256.digest(attempt.verifier), padding: false))
    token = JSON::JWT.new({ iss: OidcClient::ISSUER, sub: @subject, aud: "muzeum-test",
      iat: Time.current.to_i, exp: 5.minutes.from_now.to_i, nonce: attempt.nonce }.merge(claims))
    token.kid = "test"
    signed = token.sign(key, :RS256).to_s
    stub_request(:post, "https://auth.harvj.com/token").with { |req|
      body = Rack::Utils.parse_query(req.body)
      body["code_verifier"] == attempt.verifier && body["code"] == "one-use-code"
    }.to_return(headers: { "Content-Type" => "application/json" }, body: { access_token: "short-access", token_type: "bearer", expires_in: 300,
      id_token: signed, refresh_token: "revocable-grant" }.to_json)
    get "/oidc/callback", params: { state: attempt.state, code: "one-use-code" }
    query["state"]
  end

  def restore_oidc
    %w[OIDC_CLIENT_ID OIDC_CLIENT_SECRET OIDC_REDIRECT_URI].each { |k| @old_env.key?(k) ? ENV[k] = @old_env[k] : ENV.delete(k) }
  end
end
