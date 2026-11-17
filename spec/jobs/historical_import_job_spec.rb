require "rails_helper"

RSpec.describe HistoricalImportJob, type: :job do
  include ActiveJob::TestHelper
  let(:user) { User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "job-user", lastfm_username: "source") }
  let(:run) { user.import_runs.create!(source_username: "source", upper_bound: Time.current.to_i) }

  it "bounds transient retries and records an actionable failure" do
    importer = instance_double(Lastfm::HistoricalImporter)
    allow(Lastfm::HistoricalImporter).to receive(:new).and_return(importer)
    allow(importer).to receive(:page!).and_raise(Clients::NetworkError)
    job = described_class.new(run.id)
    job.exception_executions = { [ Clients::NetworkError, Clients::RateLimited ].to_s => 4 }
    expect { job.perform_now }.not_to have_enqueued_job(described_class)
    expect(run.reload.failed?).to be(true)
    expect(run.last_error).to include("five attempts")
  end

  it "does not import after local permission is disabled or association changed" do
    id = run.id
    user.update!(disabled_at: Time.current)
    expect(Lastfm::HistoricalImporter).not_to receive(:new)
    described_class.perform_now(id)
  end
end
