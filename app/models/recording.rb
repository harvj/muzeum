class Recording < ApplicationRecord
  has_many :recording_artists, dependent: :destroy
  has_many :artists, through: :recording_artists
  has_many :daily_listens, dependent: :destroy
  has_many :recording_surfaces, dependent: :destroy

  belongs_to :merged_into, class_name: "Recording", optional: true

  validates :title, presence: true
  validates :source, inclusion: { in: VALID_SOURCES }

  enum :status, {
    provisional: 0,
    resolved: 1,
    canonical: 2,
    merged: 3
  }
end
