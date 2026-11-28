class ReleaseArtist < ApplicationRecord
  belongs_to :release
  belongs_to :artist

  attribute :position, ArtistCreditPosition.new
end
