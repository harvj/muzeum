module RecordingResolution
  class Assessment < ApplicationRecord
    INTERPRETATION_VERSION = "workspace-evidence-v3".freeze

    self.table_name = "resolution_assessments"
  end
end
