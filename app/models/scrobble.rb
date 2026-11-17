class Scrobble < ApplicationRecord
  belongs_to :user
  belongs_to :lastfm_account, optional: true
  before_validation { self.lastfm_account ||= user&.source_account }
  belongs_to :recording, optional: true
  belongs_to :recording_surface, optional: true
end
