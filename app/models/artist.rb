class Artist < ApplicationRecord
  has_many :recording_artists, dependent: :destroy
  has_many :recordings, through: :recording_artists

  has_many :release_artists, dependent: :destroy
  has_many :releases, through: :release_artists

  validates :name, presence: true
  validates :mbid, presence: true
end
