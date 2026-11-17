require "spec_helper"
require "open3"
require "json"

RSpec.describe "Capistrano deployment/reporting integration" do
  def rehearse(scenario)
    output, errors, status = Open3.capture3("bundle", "exec", "ruby", "spec/fixtures/deployments/capistrano_hooks.rb", scenario)
    raise errors unless status.success?
    JSON.parse(output.lines.find { |line| line.start_with?("HOOK_FIXTURE:") }.delete_prefix("HOOK_FIXTURE:")).merge("stderr" => errors)
  end

  it "runs the real preflight task without logging shims, deployment phases or GitHub records" do
    result = rehearse("preflight")
    expect(result["events"].select { |kind, _| kind == "server" }.map(&:last)).to eq([ "preflight" ])
    expect(result["phase"]).to eq("unchanged")
    expect(result["creates"]).to eq(0)
  end

  it "reports success only after the server completes its final verification" do
    result = rehearse("success")
    expect(result["events"].select { |kind, _| kind == "server" }.map(&:last)).to eq(%w[begin prepare finish complete])
    expect(result["states"]).to eq(%w[in_progress success])
    expect(result["phase"]).to eq("complete")
  end

  it "cancels untouched server preparation when GitHub initiation fails" do
    result = rehearse("before_api")
    expect(result["events"].select { |kind, _| kind == "server" }.map(&:last)).to eq(%w[begin cancel])
    expect(result["phase"]).to eq("cancelled")
    expect(result["states"]).to eq([ "error" ])
  end

  it "keeps verified production available after a reporting outage and retries only reporting" do
    result = rehearse("after_api")
    expect(result["error"]).to be_nil
    expect(result["stderr"]).to include("GitHub reporting pending")
    expect(result["before_retry"]).to include("phase" => "complete", "desired" => "success", "reported" => false)
    expect(result["phase"]).to eq("complete")
    expect(result["events"].select { |kind, _| kind == "server" }.map(&:last)).to eq(%w[begin prepare finish complete])
    expect(result["states"]).to eq(%w[in_progress success])
    expect(result["creates"]).to eq(1)
  end

  it "reports failure from the retained server receipt after health failure" do
    result = rehearse("health")
    expect(result["phase"]).to eq("failed")
    expect(result["states"]).to eq(%w[in_progress failure])
  end
end
