lock "~> 3.20"
set :application, "muzeum"
set :repo_url, "git@github.com:harvj/muzeum.git"
set :deploy_to, "/var/www/muzeum"
set :branch, -> { fetch(:approved_revision) }
set :keep_releases, 5
set :bundle_flags, "--quiet"
require_relative "../lib/muzeum_release_package"
append :linked_files, *MuzeumReleasePackage::LINKED_FILES
append :linked_dirs, *MuzeumReleasePackage::LINKED_DIRECTORIES
# capistrano-rails defaults to shared assets; the sealed manifest must be release-local.
Rake::Task["deploy:set_linked_dirs"].clear_actions if Rake::Task.task_defined?("deploy:set_linked_dirs")

before "deploy:symlink:linked_dirs", "muzeum:shared_runtime"
set :default_env, { "RAILS_ENV" => "production", "RBENV_VERSION" => "3.4.12", "BUNDLE_PATH" => "/var/www/muzeum/shared/bundle" }
set :bundle_version, 4
set :bundle_jobs, 2
SSHKit.config.command_map[:bundle] = "/home/muzeum/.rbenv/shims/bundle"
set :assets_prefix, "assets"
set :assets_manifests, [ "public/assets/.manifest.json" ]
set :rails_env, "production"
set :assets_roles, [ :web ]
set :default_env, fetch(:default_env).merge("PATH" => "/home/muzeum/.rbenv/shims:/home/muzeum/.rbenv/bin:$PATH", "SECRET_KEY_BASE_DUMMY" => "1")
set :ssh_options, { forward_agent: false, verify_host_key: :always, auth_methods: %w[publickey], non_interactive: true }

require_relative "../lib/muzeum_deployment_revision"
require_relative "../lib/muzeum_release_identity_tasks"
require_relative "../lib/muzeum_shell_preflight"
include MuzeumReleaseIdentityTasks
require_relative "../lib/muzeum_deployment_reporting"
require "digest"
require "securerandom"

def muzeum_reporting
  git_directory = MuzeumDeploymentRevision.command("git", "rev-parse", "--git-common-dir")
  MuzeumDeploymentReporting::Outbox.new(File.join(git_directory, "muzeum-deployments"))
end

def muzeum_verify_helper
  on primary(:app) do
    installed = capture(:sudo, "-n", "/usr/local/sbin/muzeum-deploy", "version").strip
    expected = Digest::SHA256.hexdigest(File.binread(File.expand_path("../ops/deploy/muzeum_deploy.py", __dir__)) + File.binread(File.expand_path("../ops/deploy/inspect.rb", __dir__)))
    raise "Reviewed deployment helper version mismatch" unless installed == expected
  end
end

def muzeum_publish_result(token, sha)
  receipt = nil
  on primary(:app) do
    receipt = JSON.parse(capture(:sudo, "-n", "/usr/local/sbin/muzeum-deploy", "receipt", sha, token))
  end
  result = muzeum_reporting.reconcile(token, receipt)
  puts "GitHub deployment #{result.fetch(:id)}: #{result.fetch(:state)}; receipt #{token}.json"
  warn "Deployment remains incomplete; inspect server receipt #{token}.json" unless result.fetch(:terminal)
rescue StandardError
  warn "GitHub reporting pending; production result is retained. Retry: cap production 'muzeum:report[#{token}]'"
end

namespace :muzeum do
  task :shared_runtime do
    on roles(:app) do
      execute :mkdir, "-p", shared_path.join("tmp/pids"), shared_path.join("tmp/sockets"), shared_path.join("tmp/storage")
    end
  end

  desc "Verify the exact local revision and installed production readiness without deploying"
  task :preflight do
    approval = MuzeumDeploymentRevision.resolve!
    puts "Preflight revision #{approval.fetch(:sha)}; CI #{approval.fetch(:ci)}"
    muzeum_verify_helper
    on primary(:app) do
      execute :sudo, "-n", "/usr/local/sbin/muzeum-deploy", "preflight"
    end
  end

  desc "Synchronize verified publication with the running release without a restart"
  task :sync_release, [ :tag, :deployment, :status ] do |_, args|
    on primary(:app) do
      muzeum_sync_release(args.fetch(:tag).to_s, deployment: args[:deployment], status: args[:status],
        ruby: "/home/muzeum/.rbenv/shims/ruby", command: MuzeumDeploymentRevision.method(:command))
    end
  end

  desc "Retry GitHub reporting from the existing server receipt; never redeploy"
  task :report, [ :token ] do |_task, args|
    token = args.fetch(:token)
    record = muzeum_reporting.read(token)
    muzeum_publish_result(token, record.fetch("sha"))
  end

  task :authorize do
    approval = MuzeumDeploymentRevision.resolve!
    MuzeumShellPreflight.verify!(approval.fetch(:sha))
    set :approved_revision, approval.fetch(:sha)
    set :branch, approval.fetch(:sha)
    set :deployment_token, SecureRandom.hex(16)
    puts "Muzeum immutable revision #{fetch(:approved_revision)}; CI #{approval.fetch(:ci)}"
    outbox = muzeum_reporting
    outbox.check_clear!
    muzeum_verify_helper
    on primary(:app) do
      execute :sudo, "-n", "/usr/local/sbin/muzeum-deploy", "begin", fetch(:approved_revision), fetch(:deployment_token)
      set :deployment_lock_acquired, true
    end
    begin
      outbox.create(fetch(:approved_revision), fetch(:deployment_token))
      set :deployment_reporting_started, true
      outbox.start(fetch(:deployment_token))
    rescue StandardError, Interrupt
      on primary(:app) do
        execute :sudo, "-n", "/usr/local/sbin/muzeum-deploy", "cancel", fetch(:approved_revision), fetch(:deployment_token)
        set :deployment_lock_acquired, false
      end
      muzeum_publish_result(fetch(:deployment_token), fetch(:approved_revision)) if fetch(:deployment_reporting_started, false)
      set :deployment_reporting_finalized, true
      raise "GitHub initiation failed; production deployment was not started; inspect local reporting outbox"
    end
    outbox.attempted(fetch(:deployment_token))
  end

  task :prepare do
    on primary(:app) do
      target = capture(:cat, release_path.join("VERSION"))
      candidate = muzeum_package_identity(release_path, fetch(:approved_revision), target, ruby: "/home/muzeum/.rbenv/shims/ruby")
      muzeum_reporting.bind_artifact(fetch(:deployment_token), candidate)
      set :packaged_candidate, candidate
      execute :sudo, "-n", "/usr/local/sbin/muzeum-deploy", "prepare", fetch(:approved_revision), fetch(:deployment_token), release_path
    end
  end

  task :finish do
    on primary(:app) do
      execute :sudo, "-n", "/usr/local/sbin/muzeum-deploy", "finish", fetch(:approved_revision), fetch(:deployment_token)
    end
  end

  task :complete do
    on primary(:app) do
      artifact = capture(:readlink, "-f", current_path)
      candidate = muzeum_verify_artifact(release_path, fetch(:approved_revision), ruby: "/home/muzeum/.rbenv/shims/ruby")
      unless artifact == release_path.to_s && candidate == fetch(:packaged_candidate)
        raise "Running artifact differs from the packaged candidate"
      end
      execute :sudo, "-n", "/usr/local/sbin/muzeum-deploy", "complete", fetch(:approved_revision), fetch(:deployment_token)
      set :deployment_lock_acquired, false
    end
    muzeum_publish_result(fetch(:deployment_token), fetch(:approved_revision))
    set :deployment_reporting_finalized, true
  end

  task :failed do
    begin
      if fetch(:deployment_lock_acquired, false)
        on primary(:app) do
          execute :sudo, "-n", "/usr/local/sbin/muzeum-deploy", "fail", fetch(:approved_revision), fetch(:deployment_token)
        end
      end
    ensure
      if fetch(:deployment_reporting_started, false) && !fetch(:deployment_reporting_finalized, false)
        muzeum_publish_result(fetch(:deployment_token), fetch(:approved_revision))
        set :deployment_reporting_finalized, true
      end
    end
  end

  task :refuse_rollback do
    abort "Automatic rollback is unavailable: review a schema-compatible forward deployment; never reverse migrations or restore live data automatically"
  end
end
before "deploy:starting", "muzeum:authorize"
before "deploy:reverting", "muzeum:refuse_rollback"
after "deploy:updated", "muzeum:prepare"
after "deploy:published", "muzeum:finish"
after "deploy:finished", "muzeum:complete"
after "deploy:failed", "muzeum:failed"

at_exit do
  if fetch(:deployment_reporting_started, false) && !fetch(:deployment_reporting_finalized, false)
    muzeum_publish_result(fetch(:deployment_token), fetch(:approved_revision))
  end
end
