require "spec_helper"
require "tmpdir"
require_relative "../../lib/muzeum_deployment_reporting"
require_relative "../support/deployment_api_fixture"

RSpec.describe MuzeumDeploymentReporting::Outbox do
  let(:sha) { "a" * 40 }
  let(:token) { "b" * 32 }
  let(:api) { DeploymentApiFixture.new }
  let(:receipt) { { "sha" => sha, "token" => token, "phase" => "complete", "health" => "passed" } }

  around do |example|
    Dir.mktmpdir("muzeum-reporting") do |root|
      @outbox = described_class.new(root, api: api)
      example.run
    end
  end

  def start_attempt
    @outbox.create(sha, token)
    @outbox.start(token)
    @outbox.attempted(token)
  end

  it "tracks exact SHA and in_progress, then success only after verified completion" do
    start_attempt
    expect(api.creates.first).to include(ref: sha, environment: "production", auto_merge: false, required_contexts: [])
    expect(api.creates.first[:payload]).to include(muzeum_token: token, receipt: "#{token}.json")
    expect(api.states).to eq([ "in_progress" ])
    @outbox.reconcile(token, receipt)
    expect(api.states).to eq([ "in_progress", "success" ])
    expect(api.statuses.last).to include(environment_url: "https://muzeum.fm")
    expect(@outbox.read(token)).to include("reported" => true, "phase" => "complete")
  end

  it "reports failure for an attempted deployment and error for a cancelled initiation" do
    start_attempt
    @outbox.reconcile(token, receipt.merge("phase" => "failed"))
    expect(api.states.last).to eq("failure")
  end

  it "uses error for cancelled work before any application deployment" do
    @outbox.create(sha, token)
    @outbox.start(token)
    @outbox.reconcile(token, receipt.merge("phase" => "cancelled"))
    expect(api.states.last).to eq("error")
  end

  it "does not claim success for publication, interrupted or incomplete verification" do
    start_attempt
    @outbox.reconcile(token, receipt.merge("phase" => "ready_to_publish"))
    expect(api.states).to eq([ "in_progress" ])
    expect(@outbox.read(token)["reported"]).to eq(false)
    expect { @outbox.reconcile(token, receipt.merge("health" => "failed")) }.to raise_error(/verification/)
    expect(api.states).not_to include("success")
  end

  it "retains a pre-deployment GitHub outage and retries a cancelled result without deploying" do
    @outbox.create(sha, token)
    api.fail_next = :before
    expect { @outbox.start(token) }.to raise_error(MuzeumDeploymentReporting::Error)
    @outbox.reconcile(token, receipt.merge("phase" => "cancelled"))
    expect(api.creates.size).to eq(1)
    expect(api.states).to eq([ "error" ])
  end

  it "retains actual success after an API outage and retries status without creating a deployment" do
    start_attempt
    api.fail_next = :before
    expect { @outbox.reconcile(token, receipt) }.to raise_error(MuzeumDeploymentReporting::Error)
    expect(@outbox.read(token)).to include("phase" => "complete", "desired" => "success", "reported" => false)
    expect { @outbox.create(sha, "c" * 32) }.to raise_error(/pending/)
    @outbox.reconcile(token, receipt)
    @outbox.reconcile(token, receipt)
    expect(api.creates.size).to eq(1)
    expect(api.states).to eq([ "in_progress", "success" ])
  end

  it "recovers a lost create response by token lookup without a second POST" do
    @outbox.create(sha, token)
    api.fail_next = :after_create
    expect { @outbox.start(token) }.to raise_error(MuzeumDeploymentReporting::Error)
    @outbox.reconcile(token, receipt.merge("phase" => "cancelled"))
    expect(api.creates.size).to eq(1)
    expect(api.states).to eq([ "error" ])
  end

  it "never repeats an ambiguous create when lookup cannot yet see it" do
    @outbox.create(sha, token)
    api.fail_next = :after_create
    expect { @outbox.start(token) }.to raise_error(MuzeumDeploymentReporting::Error)
    api.hide_records = true
    expect { @outbox.start(token) }.to raise_error(/Ambiguous/)
    expect(api.creates.size).to eq(1)
  end

  it "reconciles a lost status response without duplicating the status" do
    start_attempt
    api.fail_next = :after_status
    expect { @outbox.reconcile(token, receipt) }.to raise_error(MuzeumDeploymentReporting::Error)
    @outbox.reconcile(token, receipt)
    expect(api.states).to eq([ "in_progress", "success" ])
  end

  it "refuses contradictory terminal records and forged receipts" do
    start_attempt
    @outbox.reconcile(token, receipt)
    expect { @outbox.reconcile(token, receipt.merge("phase" => "failed")) }.to raise_error(/Conflicting/)
    expect { @outbox.reconcile(token, receipt.merge("sha" => "d" * 40)) }.to raise_error(/identity/)
    expect(api.states).to eq([ "in_progress", "success" ])
  end

  it "refuses to overwrite externally failed or retired deployment statuses" do
    start_attempt
    api.statuses << { state: "inactive" }
    expect { @outbox.reconcile(token, receipt) }.to raise_error(/Conflicting GitHub/)
    expect(api.states).to eq(%w[in_progress inactive])
  end

  it "refuses multiple matching GitHub deployment records" do
    start_attempt
    api.duplicate!
    # Reopen the same outbox without a saved ID to exercise ambiguous-response recovery.
    path = @outbox.instance_variable_get(:@root) + "/#{token}.json"
    record = JSON.parse(File.read(path))
    record.delete("deployment_id")
    File.write(path, JSON.generate(record))
    expect { @outbox.start(token) }.to raise_error(/Duplicate/)
    expect(api.creates.size).to eq(1)
  end
end
