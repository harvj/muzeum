class Recording < ApplicationRecord
  has_many :recording_artists, dependent: :destroy
  has_many :artists, through: :recording_artists
  has_many :daily_listens, dependent: :destroy

  validates :title, presence: true
end
