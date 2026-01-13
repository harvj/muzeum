class RecordingArtist < ApplicationRecord
  belongs_to :recording
  belongs_to :artist

  VALID_ROLES = %w[
    primary
    featured
    composer
    performer
    remixer
  ].freeze

  VALID_SOURCES = %w[
    inferred
    musicbrainz
    user_override
  ].freeze

  validates :role, inclusion: { in: VALID_ROLES }
  validates :source, inclusion: { in: VALID_SOURCES }
end
