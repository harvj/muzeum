class Artist < ApplicationRecord
  has_many :recording_artists, dependent: :destroy
  has_many :reocrdings, through: :recording_artists

  validates :name, presence: true
end
