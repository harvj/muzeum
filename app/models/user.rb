class User < ApplicationRecord
  has_many :sessions, dependent: :delete_all
  has_many :daily_listens, dependent: :restrict_with_exception
  has_many :import_runs, dependent: :restrict_with_exception
  has_many :scrobbles, dependent: :restrict_with_exception

  has_many :user_lastfm_accounts
  has_many :lastfm_accounts, through: :user_lastfm_accounts
  after_create :associate_legacy_name, if: -> { lastfm_username.present? }

  def source_account
    lastfm_accounts.where(user_lastfm_accounts: { revoked_at: nil }).first
  end

  def archive_observations
    Scrobble.where(lastfm_account_id: user_lastfm_accounts.active.select(:lastfm_account_id))
  end

  normalizes :email_address, with: ->(email) { email.strip.downcase }
  validates :oidc_subject, uniqueness: { scope: :oidc_issuer }, allow_nil: true
  after_update :revoke_sessions, if: :saved_change_to_disabled_at?

  def login_enabled?
    oidc_issuer == OidcClient::ISSUER && oidc_subject.present? && disabled_at.nil?
  end

  private

  def associate_legacy_name
    LastfmAccount.associate!(self, lastfm_username)
  end

  def revoke_sessions
    sessions.delete_all
  end
end
