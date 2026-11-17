class OidcAttempt < ApplicationRecord
  def self.consume!(state, browser)
    transaction do
      attempt = lock.find_by!(state: state)
      attempt.destroy!
      return nil if attempt.expires_at <= Time.current
      return nil unless ActiveSupport::SecurityUtils.secure_compare(attempt.browser_digest, Digest::SHA256.hexdigest(browser.to_s))
      attempt
    end
  end
end
