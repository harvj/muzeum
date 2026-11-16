class User < ApplicationRecord
  has_secure_password validations: false
  has_many :sessions, dependent: :delete_all
  has_many :daily_listens, dependent: :restrict_with_exception
  has_many :import_runs, dependent: :restrict_with_exception
  has_many :scrobbles, dependent: :restrict_with_exception

  normalizes :email_address, with: ->(email) { email.strip.downcase }
  validates :lastfm_username, uniqueness: true, allow_nil: true
  validates :email_address, presence: true, if: :activated_at?
  validates :email_address, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :email_address, uniqueness: { case_sensitive: false }, allow_nil: true
  validates :password, length: { minimum: 12, maximum: 72 }, allow_nil: true
  validates :password, confirmation: true, if: -> { password.present? }
  validates :password_digest, presence: true, if: :activated_at?
  validate :password_byte_length
  after_update :revoke_sessions, if: -> { saved_change_to_password_digest? || saved_change_to_disabled_at? }

  def login_enabled?
    activated_at.present? && disabled_at.nil? && password_digest.present?
  end

  private

  def password_byte_length
    errors.add(:password, "must be at most 72 bytes") if password && password.bytesize > 72
  end

  def revoke_sessions
    sessions.delete_all
  end
end
