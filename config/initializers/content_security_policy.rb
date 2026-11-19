Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :self
    policy.object_src :none
    policy.frame_ancestors :none
    policy.font_src :self
    policy.img_src :self, :data, "https://art.harvj.com"
    policy.script_src :self
    policy.style_src :self
    policy.connect_src :self
    # Chromium carries the initiating sign-in form policy through the OIDC redirect.
    policy.form_action :self, "https://auth.harvj.com"
  end
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
