# Isolated Capistrano task execution. Every remote operation and GitHub call is synthetic.
require "capistrano/all"
require "capistrano/setup"
require "capistrano/deploy"
require "tmpdir"
require_relative "../../support/deployment_api_fixture"
load "./config/deploy.rb"

$events = []
$phase = nil
$scenario = ARGV.fetch(0)
$artifact_path = "/var/www/muzeum/releases/20261124000000"
$artifact_identity = { "schema_version" => 1, "application" => "muzeum", "kind" => "candidate",
  "source_sha" => "a" * 40, "target_version" => "0.7.1", "candidate_number" => 1, "artifact_sha256" => "b" * 64 }
$api = DeploymentApiFixture.new
$local = Dir.mktmpdir("muzeum-cap-hooks")
$box = MuzeumDeploymentReporting::Outbox.new($local, api: $api)

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

  def self.resolve!
    { sha: "a" * 40, ci: "https://example.test/ci" }
  end
end

module MuzeumShellPreflight
  def self.verify!(revision)
    $events << [ "shell preflight", revision ]
    raise "Shell review rejected" if $scenario == "shell_rejected"
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

def self.test(*_args)
  false
end

def self.capture(*args)
  if args.first == :readlink
    $scenario == "artifact_changed" ? "/var/www/muzeum/releases/20261124000001" : $artifact_path
  elsif args.first.to_s.end_with?("/ruby")
    $events << [ "artifact", args[2] ]
    $artifact_identity.to_json
  elsif args.last.to_s.end_with?("/VERSION")
    "0.7.1"
  elsif args.first == :cat
    $events << [ "remote revision", args.last ]
    "a" * 40
  elsif args.last == "version"
    Digest::SHA256.hexdigest(File.binread("ops/deploy/muzeum_deploy.py") + File.binread("ops/deploy/inspect.rb"))
  else
    JSON.generate({ sha: fetch(:approved_revision), token: fetch(:deployment_token), phase: $phase, health: "passed" })
  end
end

def self.execute(*args)
  return if args.first == :mkdir

  if args.first.to_s.end_with?("/ruby")
    $events << [ "metadata only", *args.drop(1) ]
    return
  end

  phase = args.fetch(3)
  $events << [ "server", phase ]
  $phase = { "begin" => "prepared_checkout", "prepare" => "ready_to_publish", "finish" => "verified", "complete" => "complete", "fail" => "failed", "cancel" => "cancelled", "preflight" => "unchanged" }.fetch(phase)
  $api.fail_next = :before if phase == "begin" && $scenario == "before_api"
  $api.fail_next = :before if phase == "complete" && $scenario == "after_api"
  if phase == "finish" && $scenario == "health"
    $phase = "failed"
    raise "Synthetic server health failure"
  end
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
  set :release_path, Pathname($artifact_path)
  Rake::Task["muzeum:prepare"].invoke
  Rake::Task["muzeum:finish"].invoke
  Rake::Task["muzeum:complete"].invoke
rescue StandardError
  error = "expected synthetic failure"
  begin
    Rake::Task["muzeum:failed"].invoke
  rescue StandardError
    nil
  end
end
if $scenario == "shell_rejected"
  puts "HOOK_FIXTURE:" + JSON.generate({ events: $events, error: error, creates: $api.creates.size })
  FileUtils.remove_entry($local)
  exit 0
end
before_retry = $box.read(fetch(:deployment_token))
if $scenario == "after_api"
  2.times do
    Rake::Task["muzeum:report"].reenable
    Rake::Task["muzeum:report"].invoke(fetch(:deployment_token))
  end
end
puts "HOOK_FIXTURE:" + JSON.generate({ events: $events, phase: $phase, error: error, before_retry: before_retry, final: $box.read(fetch(:deployment_token)), states: $api.states, statuses: $api.statuses, creates: $api.creates.size })
FileUtils.remove_entry($local)
