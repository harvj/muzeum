require "rails_helper"

RSpec.describe "Production queue consumption" do
  it "configures workers that actually consume the import and operator probe job queues" do
    workers = SolidQueue::Configuration.new.configured_processes.select { |process| process.kind == :worker }
    queues = workers.flat_map { |process| Array(process.attributes.fetch(:queues)) }
    expect(queues).to include(HistoricalImportJob.queue_name, OpsProbeJob.queue_name)
    expect(queues).not_to include("*")
  end
end
