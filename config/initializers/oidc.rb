# Derive separate encryption keys from Rails' durable secret; no new ephemeral keys.
Rails.application.config.active_record.encryption.primary_key = Rails.application.key_generator.generate_key("muzeum/grant/primary", 32).unpack1("H*")
Rails.application.config.active_record.encryption.deterministic_key = Rails.application.key_generator.generate_key("muzeum/grant/deterministic", 32).unpack1("H*")
Rails.application.config.active_record.encryption.key_derivation_salt = "muzeum/oidc/v1"
OpenIDConnect.http_config do |http|
  http.options.timeout = 8
  http.options.open_timeout = 3
end
