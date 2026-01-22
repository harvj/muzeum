class Release < ApplicationRecord
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
