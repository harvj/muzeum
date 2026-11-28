class RecordingArtist < ApplicationRecord
  belongs_to :recording
  belongs_to :artist

  attribute :position, ArtistCreditPosition.new

  enum :role, {
    primary: 0,
    featured: 1,
    remixer: 2
  }
end
