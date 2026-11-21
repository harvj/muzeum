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
    expect(result["events"]).to eq([ [ "server", "preflight" ] ])
    expect(result["phase"]).to eq("unchanged")
    expect(result["creates"]).to eq(0)
  end

  it "reconciles only metadata after verifying an already deployed revision" do
    result = rehearse("sync")
    expect(result["events"]).to eq([
      [ "remote revision", "/var/www/muzeum/current/REVISION" ],
      [ "github", "release" ], [ "github", "api" ],
      [ "metadata only", "/var/www/muzeum/current/lib/muzeum_published_release.rb", "a" * 40, "v0.2.1" ]
    ])
    expect(result["creates"]).to eq(0)
    expect(rehearse("sync_mismatch")["events"].map(&:first)).to eq([ "remote revision", "github", "github" ])
  end

  it "reports success only after the server completes its final verification" do
    result = rehearse("success")
    expect(result["events"]).to eq([
      [ "server", "begin" ],
      [ "server", "prepare" ], [ "server", "finish" ], [ "server", "complete" ]
    ])
    expect(result["states"]).to eq(%w[in_progress success])
    expect(result["phase"]).to eq("complete")
  end

  it "stops before contacting the server when Application Shell preflight fails" do
    result = rehearse("shell_blocked")
    expect(result["error"]).to include("Application Shell preflight failed")
    expect(result["events"]).to be_empty
    expect(result["creates"]).to eq(0)
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

  it "probes the explicit Ruby and frozen Bundler in the release directory" do
    result = rehearse("runtime_probe")
    runtime = "/opt/muzeum/ruby-3.4.13/bin"
    bundle = "#{runtime}/ruby #{runtime}/bundle"
    expect(result["events"]).to match([
      [ "directory", "/disposable/release" ],
      [ "environment", { "BUNDLE_IGNORE_CONFIG" => "1", "BUNDLE_FROZEN" => "true", "BUNDLE_WITHOUT" => "development:test" } ],
      [ "command", "#{runtime}/ruby", "-e", include("RUBY_VERSION") ],
      [ "command", bundle, "--version" ],
      [ "command", bundle, "check" ]
    ])
    expect(result["rake"]).to start_with("#{bundle} exec ")
    expect(result["default_env"]).to include("PATH" => "#{runtime}:/usr/bin:/bin",
      "BUNDLE_PATH" => "/var/www/muzeum/shared/bundle/ruby-3.4.13")
  end

  it "stamps the reviewed version only after the packaged revision matches" do
    expected_sha = "1633c96d63c1a44e678e95292466ab49c0442103"
    expect(rehearse("stamp")["events"]).to eq([
      [ "remote revision", "/disposable/release/REVISION" ],
      [ "stamp", "#{expected_sha} v0.3.4\n", "/disposable/release/REVIEWED_RELEASE" ],
      [ "server", "prepare" ]
    ])
    expect(rehearse("stamp_mismatch")["events"]).to eq([ [ "remote revision", "/disposable/release/REVISION" ] ])
  end
end
