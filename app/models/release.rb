class Release < ApplicationRecord
  has_many :release_artists, dependent: :destroy
  has_many :artists, through: :release_artists

  has_many :release_recordings, dependent: :destroy
  has_many :recordings, dependent: :destroy

  enum :primary_type, {
    album: 0,
    ep: 1,
    single: 2,
    compilation: 3
  }

  enum :secondary_type, {
    official: 0,
    live: 1,
    soundtrack: 2,
    remix: 4,
    reissue: 5
  }
end
