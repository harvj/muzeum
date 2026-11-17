class LastfmSchedulerJob < ApplicationJob
  queue_as :imports
  def perform
    Lastfm::Scheduler.dispatch!
  end
end
