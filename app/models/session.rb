class Session < ApplicationRecord
  belongs_to :user
  encrypts :grant_token
  scope :unexpired, -> { where(expires_at: Time.current..) }
end
