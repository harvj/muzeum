# Internal operator-only queue/restart probe; no public endpoint or user data.
class OpsProbeJob < ApplicationJob
  queue_as :default

  def perform(reference)
    raise ArgumentError unless reference.match?(/\A[a-f0-9]{32}\z/)
    Rails.cache.write("muzeum/worker-probe/#{reference}", Time.current.utc.iso8601, expires_in: 1.hour)
  end
end
