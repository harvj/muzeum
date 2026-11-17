module RecordingResolution
  class RequestCache < ApplicationRecord
    self.table_name = "resolution_request_cache"
    self.primary_key = "request_key"
  end
end
