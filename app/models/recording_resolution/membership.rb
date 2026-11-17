module RecordingResolution
  class Membership < ApplicationRecord
    self.table_name = "resolution_memberships"
    self.primary_key = "scrobble_id"
  end
end
