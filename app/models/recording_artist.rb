class RecordingArtist < ApplicationRecord
  belongs_to :recording
  belongs_to :artist

  enum :role, {
    primary: 0,
    featured: 1,
    remixer: 2
  }
end
