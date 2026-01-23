class Scrobble < ApplicationRecord
  belongs_to :user
  belongs_to :recording, optional: true
  belongs_to :recording_surface, optional: true
end
