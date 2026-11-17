class User < ApplicationRecord
  has_many :sessions, dependent: :delete_all
  has_many :daily_listens, dependent: :restrict_with_exception
  has_many :import_runs, dependent: :restrict_with_exception
  has_many :scrobbles, dependent: :restrict_with_exception

  normalizes :email_address, with: ->(email) { email.strip.downcase }
  validates :lastfm_username, uniqueness: { case_sensitive: false }, allow_nil: true
  validates :oidc_subject, uniqueness: { scope: :oidc_issuer }, allow_nil: true
  after_update :revoke_sessions, if: :saved_change_to_disabled_at?

  def login_enabled?
    oidc_issuer == OidcClient::ISSUER && oidc_subject.present? && disabled_at.nil?
  end

  private

  def revoke_sessions
    sessions.delete_all
  end
end
