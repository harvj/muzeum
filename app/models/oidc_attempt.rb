class OidcAttempt < ApplicationRecord
  def self.consume!(state, browser_digest)
    transaction do
      attempt = lock.find_by(state:)
      next unless attempt && ActiveSupport::SecurityUtils.secure_compare(attempt.browser_digest, browser_digest)

      attempt.destroy!
      attempt if attempt.expires_at > Time.current
    end
  end
end
