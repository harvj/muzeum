require "rails_helper"
require "fugit"

RSpec.describe "Production queue consumption" do
  it "configures workers that actually consume the import and operator probe job queues" do
    workers = SolidQueue::Configuration.new.configured_processes.select { |process| process.kind == :worker }
    queues = workers.flat_map { |process| Array(process.attributes.fetch(:queues)) }
    expect(queues).to include(HistoricalImportJob.queue_name, OpsProbeJob.queue_name)
    expect(queues).not_to include("*")
  end
end

RSpec.describe "Central synchronization schedule" do
  it "registers the single dispatcher at one-second cadence without per-account cron jobs" do
    configuration = YAML.safe_load(Rails.root.join("config/recurring.yml").read).fetch("production")
    task = configuration.fetch("lastfm_synchronization")
    expect(task.fetch("class")).to eq("LastfmSchedulerJob")
    expect(Fugit.parse(task.fetch("schedule"), multi: :fail)).to be_a(Fugit::Cron)
    expect(task.fetch("schedule")).to eq("every second")
    expect(LastfmSchedulerJob.queue_name).to eq("imports")
  end
end
