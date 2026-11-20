module LoginDestination
  PATH = %r{\A/(?:archive(?:/summary)?|(?:artists|releases|recordings)(?:/[1-9][0-9]*)?|resolution(?:/[1-9][0-9]*(?:/release_batch)?)?)\z}

  def self.validate(value)
    return unless value.is_a?(String) && value.bytesize <= 2_048 && !value.match?(/[[:cntrl:]\\#]/)

    path, = value.split("?", 2)
    value if PATH.match?(path.to_s)
  end

  def self.handoff(destination)
    verifier.generate(destination, purpose: :protected_login, expires_in: 2.minutes)
  end

  def self.from_handoff(token)
    validate(verifier.verified(token, purpose: :protected_login)) if token.is_a?(String)
  end

  def self.verifier
    Rails.application.message_verifier(:oidc_destination)
  end
  private_class_method :verifier
end
