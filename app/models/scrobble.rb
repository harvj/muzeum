class Scrobble < ApplicationRecord
  belongs_to :user
  belongs_to :recording, optional: true
end
