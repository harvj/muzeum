class ApplicationShellEvidence
  USERNAME = /\A[a-z0-9][a-z0-9_-]{0,31}\z/
  DESTINATION = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  FIELDS = %w[aud eligible_destination_ids exp grant_binding iat iss preferred_username sub version].freeze

  def self.validate(response, subject:, client_id:, grant:, now: Time.current.to_i)
    return unless response.is_a?(Hash) && response["active"] == true

    evidence = response["application_shell"]
    return unless evidence.is_a?(Hash) && evidence.keys.sort == FIELDS
    return unless evidence.values_at("version", "iss", "aud", "sub", "grant_binding") ==
      [ "1", OidcClient::ISSUER, client_id, subject, Digest::SHA256.hexdigest(grant) ]

    issued, expires = evidence.values_at("iat", "exp")
    return unless issued.is_a?(Integer) && expires.is_a?(Integer) &&
      issued <= now && now < expires && (expires - issued).between?(1, 60)

    name, destinations = evidence.values_at("preferred_username", "eligible_destination_ids")
    return unless name.is_a?(String) && USERNAME.match?(name) && destinations.is_a?(Array) &&
      destinations.uniq == destinations && destinations.all? { |id| id.is_a?(String) && DESTINATION.match?(id) }

    { username: name, destinations:, expires_at: expires }
  end
end
