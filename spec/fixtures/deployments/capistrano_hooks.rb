# Isolated Capistrano task execution. Every remote operation and GitHub call is synthetic.
require "capistrano/all"
require "capistrano/setup"
require "capistrano/deploy"
require "capistrano/bundler"
Rake.application.load_imports
require "tmpdir"
require_relative "../../support/deployment_api_fixture"
load "./config/deploy.rb"

$events = []
$phase = nil
$scenario = ARGV.fetch(0)
$api = DeploymentApiFixture.new
$local = Dir.mktmpdir("muzeum-cap-hooks")
$box = MuzeumDeploymentReporting::Outbox.new($local, api: $api)

# Exercise the local command boundary without contacting the publisher.
preflight = File.join($local, "application-shell-preflight")
File.write(preflight, <<~SH)
  #!/bin/sh
  test "$#" -eq 6 &&
    test "$1 $2 $3 $4 $5 $6" = "--app muzeum --revision #{MuzeumDeploymentRevision::LEGACY_RUNTIME} --review $APPLICATION_SHELL_REVIEW" ||
    exit 2
  exit #{$scenario == "shell_blocked" ? 1 : 0}
SH
File.chmod(0o700, preflight)
ENV["APPLICATION_SHELL_PREFLIGHT"] = preflight
ENV["APPLICATION_SHELL_REVIEW"] = File.join($local, "review.json")

module MuzeumDeploymentRevision
  def self.command(*args)
    $events << [ "github", args[1] ]
    case args[1]
    when "release"
      JSON.generate(tagName: "v0.2.1", isDraft: false, isPrerelease: false, publishedAt: "2026-11-19T06:37:00Z")
    when "api"
      $scenario == "sync_mismatch" ? "b" * 40 : "a" * 40
    end
  end

  def self.authorization!(_checkout)
    { sha: LEGACY_RUNTIME, ci: "https://example.test/ci", version: "v0.9.0", envelope: "fixture-envelope" }
  end

  def self.resolve!
    { sha: "a" * 40, ci: "https://example.test/ci" }
  end
end

def self.muzeum_reporting
  $box
end

def self.primary(_role)
  :disposable_fixture
end

def self.on(_server)
  yield
end

def self.capture(*args)
  if args.first == :cat
    $events << [ "remote revision", args.last ]
    $scenario == "stamp" ? "b" * 40 : "a" * 40
  elsif args.last == "version"
    paths = %w[deploy/muzeum_deploy.py deploy/inspect.rb runtime/muzeum_runtime.py deploy/release_authorization.py provision/muzeum-migrate]
    Digest::SHA256.hexdigest(paths.map { |path| File.binread("ops/#{path}") }.join)
  else
    JSON.generate({ sha: fetch(:approved_revision), token: fetch(:deployment_token), phase: $phase, health: "passed" })
  end
end

def self.execute(*args)
  if args.first.to_s.end_with?("/ruby")
    $events << [ "metadata only", *args.drop(1) ]
    return
  end

  phase = args.fetch(3)
  if phase == "begin-authorized"
    raise "Missing signed envelope" unless args.last == "fixture-envelope"

    phase = "begin"
  end
  $events << [ "server", phase ]
  $phase = { "begin" => "prepared_checkout", "prepare" => "ready_to_publish", "finish" => "verified", "complete" => "complete", "fail" => "failed", "cancel" => "cancelled", "preflight" => "unchanged" }.fetch(phase)
  $api.fail_next = :before if phase == "begin" && $scenario == "before_api"
  $api.fail_next = :before if phase == "complete" && $scenario == "after_api"
  if phase == "finish" && $scenario == "health"
    $phase = "failed"
    raise "Synthetic server health failure"
  end
end

def self.upload!(contents, destination)
  $events << [ "stamp", contents.read, destination.to_s ]
end

if $scenario == "runtime_probe"
  set :bundle_bins, %w[rake rails]
  set :bundle_without, "development:test"
  set :approved_revision, "b" * 40
  set :release_path, Pathname("/disposable/release")
  SSHKit.config.command_map.prefix[:rake] << "bundle exec"
  def self.capture(*)
    fetch(:approved_revision)
  end

  def self.within(directory)
    $events << [ "directory", directory.to_s ]
    yield
  end

  def self.with(environment)
    $events << [ "environment", environment ]
    yield
  end

  def self.execute(command, *args)
    $events << [ "command", SSHKit.config.command_map[command], *args ]
  end

  muzeum_configure_release_runtime
  Rake::Task["muzeum:probe_release_runtime"].invoke
  puts "HOOK_FIXTURE:" + JSON.generate({ events: $events, rake: SSHKit.config.command_map[:rake],
    default_env: SSHKit.config.default_env })
  FileUtils.remove_entry($local)
  exit 0
end

if %w[stamp stamp_mismatch].include?($scenario)
  set :approved_revision, "b" * 40
  set :reviewed_release_version, "v0.3.4"
  set :deployment_token, "a" * 32
  set :release_path, Pathname("/disposable/release")
  begin
    Rake::Task["muzeum:prepare"].invoke
  rescue RuntimeError => error
    raise unless $scenario == "stamp_mismatch" && error.message.include?("Unexpected reviewed release metadata")
  end
  puts "HOOK_FIXTURE:" + JSON.generate({ events: $events })
  FileUtils.remove_entry($local)
  exit 0
end

if %w[sync sync_mismatch].include?($scenario)
  begin
    Rake::Task["muzeum:sync_release"].invoke("v0.2.1")
  rescue RuntimeError => error
    raise unless $scenario == "sync_mismatch" && error.message.include?("does not match")
  end
  puts "HOOK_FIXTURE:" + JSON.generate({ events: $events, creates: $api.creates.size })
  FileUtils.remove_entry($local)
  exit 0
end

if $scenario == "preflight"
  Rake::Task["muzeum:preflight"].invoke
  puts "HOOK_FIXTURE:" + JSON.generate({ events: $events, phase: $phase, creates: $api.creates.size })
  FileUtils.remove_entry($local)
  exit 0
end

error = nil
begin
  Rake::Task["muzeum:authorize"].invoke
  set :release_path, "/disposable/release"
  Rake::Task["muzeum:prepare"].invoke
  Rake::Task["muzeum:finish"].invoke
  Rake::Task["muzeum:complete"].invoke
rescue StandardError => failure
  error = failure.message
  begin
    Rake::Task["muzeum:failed"].invoke
  rescue StandardError
    nil
  end
end
token = fetch(:deployment_token)
report_started = fetch(:deployment_reporting_started, false)
before_retry = $box.read(token) if report_started
if $scenario == "after_api"
  2.times do
    Rake::Task["muzeum:report"].reenable
    Rake::Task["muzeum:report"].invoke(fetch(:deployment_token))
  end
end
puts "HOOK_FIXTURE:" + JSON.generate({ events: $events, phase: $phase, error: error, before_retry: before_retry, final: report_started ? $box.read(token) : nil, states: $api.states, creates: $api.creates.size })
FileUtils.remove_entry($local)
