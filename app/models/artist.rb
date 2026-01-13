class Artist < ApplicationRecord
  has_many :recording_artists, dependent: :destroy
  has_many :reocrdings, through: :recording_artists

  belongs_to :merged_into, class_name: "Artist", optional: true

  validates :name, presence: true
  validates :source, inclusion: { in: VALID_SOURCES }

  enum :status, {
    provisional: 0,
    resolved: 1,
    canonical: 2,
    merged: 3
  }
end
