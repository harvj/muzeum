class Recording < ApplicationRecord
  has_many :recording_artists, dependent: :destroy
  has_many :artists, through: :recording_artists

  has_many :release_recordings, dependent: :destroy
  has_many :releases, dependent: :destroy

  has_many :daily_listens, dependent: :destroy
  has_many :recording_surfaces, dependent: :destroy

  validates :title, presence: true
  validates :mbid, presence: true
end
