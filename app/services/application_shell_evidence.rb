class ApplicationShellEvidence
  class Invalid < StandardError; end
  USERNAME = /\A[a-z0-9][a-z0-9_-]{0,31}\z/

  def self.session_binding(session)
    key = Rails.application.key_generator.generate_key("muzeum-shell-local-session")
    OpenSSL::HMAC.hexdigest("SHA256", key, [ session.id, session.user_id, Digest::SHA256.hexdigest(session.grant_token) ].join(":"))
  end

  def self.verify(data, session:, client_id:, now: Time.current.to_i)
    value = data["application_shell"] if data.is_a?(Hash) && data["active"] == true
    raise Invalid unless value.is_a?(Hash) && value.keys.sort == %w[aud eligible_destination_ids exp grant_binding iat iss preferred_username sub version]

    issued, expires, username, ids = value.values_at("iat", "exp", "preferred_username", "eligible_destination_ids")
    expected = [ "1", OidcClient::ISSUER, client_id, session.user.oidc_subject, Digest::SHA256.hexdigest(session.grant_token) ]
    unless value.values_at("version", "iss", "aud", "sub", "grant_binding") == expected &&
        issued.is_a?(Integer) && expires.is_a?(Integer) && issued <= now && now < expires && (1..60).cover?(expires - issued) &&
        username.is_a?(String) && USERNAME.match?(username) &&
        ids.is_a?(Array) && ids.size <= 64 && ids.uniq.size == ids.size && ids.all? { |id| id.is_a?(String) && id.bytesize <= 64 && ApplicationShellRegistry::ID.match?(id) }
      raise Invalid
    end
    { username: username, ids: ids, expires_at: expires }
  end
end
