class Recording < ApplicationRecord
  has_many :catalog_track_slots, dependent: :restrict_with_exception
  has_many :recording_artists, -> { order(:position, :id) }, dependent: :destroy
  has_many :artists, through: :recording_artists
  has_many :admitted_releases, -> { distinct }, through: :catalog_track_slots, source: :release

  has_many :release_recordings, dependent: :destroy
  has_many :releases, dependent: :destroy

  has_many :daily_listens, dependent: :destroy
  has_many :recording_surfaces, dependent: :destroy

  has_many :scrobbles

  validates :title, presence: true
  validates :mbid, presence: true
end
