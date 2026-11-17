class UserLastfmAccount < ApplicationRecord
  belongs_to :user
  belongs_to :lastfm_account
  scope :active, -> { where(revoked_at: nil) }

  def revoke!
    update!(revoked_at: Time.current)
  end
end
