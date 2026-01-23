class ReleaseRecording < ApplicationRecord
  belongs_to :release
  belongs_to :recording
end
