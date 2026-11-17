class RecordingResolutionJob < ApplicationJob
  queue_as :recording_resolution

  def perform(work_id)
    RecordingResolution::Processor.new(RecordingResolution::Work.find(work_id)).call
  end
end
