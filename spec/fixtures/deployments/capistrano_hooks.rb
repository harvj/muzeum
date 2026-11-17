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
$api = DeploymentApiFixture.new
$local = Dir.mktmpdir("muzeum-cap-hooks")
$box = MuzeumDeploymentReporting::Outbox.new($local, api: $api)

module MuzeumDeploymentRevision
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
  if args.last == "version"
    Digest::SHA256.hexdigest(File.binread("ops/deploy/muzeum_deploy.py") + File.binread("ops/deploy/inspect.rb"))
  else
    JSON.generate({ sha: fetch(:approved_revision), token: fetch(:deployment_token), phase: $phase, health: "passed" })
  end
end

def self.execute(*args)
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
rescue StandardError
  error = "expected synthetic failure"
  begin
    Rake::Task["muzeum:failed"].invoke
  rescue StandardError
    nil
  end
end
before_retry = $box.read(fetch(:deployment_token))
if $scenario == "after_api"
  2.times do
    Rake::Task["muzeum:report"].reenable
    Rake::Task["muzeum:report"].invoke(fetch(:deployment_token))
  end
end
puts "HOOK_FIXTURE:" + JSON.generate({ events: $events, phase: $phase, error: error, before_retry: before_retry, final: $box.read(fetch(:deployment_token)), states: $api.states, creates: $api.creates.size })
FileUtils.remove_entry($local)
