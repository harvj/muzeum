module RecordingResolution
  class Assessment < ApplicationRecord
    INTERPRETATION_VERSION = "workspace-evidence-v4".freeze

    self.table_name = "resolution_assessments"
  end
end
