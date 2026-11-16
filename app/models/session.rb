class Session < ApplicationRecord
  belongs_to :user
  scope :unexpired, -> { where(expires_at: Time.current..) }
end
