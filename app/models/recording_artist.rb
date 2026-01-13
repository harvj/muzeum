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

  validates :role, inclusion: { in: VALID_ROLES }
end
