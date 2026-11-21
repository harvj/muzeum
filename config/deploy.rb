lock "~> 3.20"
set :application, "muzeum"
set :repo_url, "git@github.com:harvj/muzeum.git"
set :deploy_to, "/var/www/muzeum"
set :branch, -> { fetch(:approved_revision) }
set :keep_releases, 5
set :bundle_flags, "--quiet"
append :linked_files, ".env"
append :linked_dirs, "storage", "log", "tmp/pids", "tmp/sockets"
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
require_relative "../lib/muzeum_published_release"
require_relative "../lib/muzeum_deployment_reporting"
require "digest"
require "securerandom"
require "stringio"

def muzeum_reporting
  git_directory = MuzeumDeploymentRevision.command("git", "rev-parse", "--git-common-dir")
  MuzeumDeploymentReporting::Outbox.new(File.join(git_directory, "muzeum-deployments"))
end

def muzeum_configure_release_runtime
  runtime = "/opt/muzeum/ruby-3.4.13/bin"
  bundle = "#{runtime}/ruby #{runtime}/bundle"
  SSHKit.config.command_map[:ruby] = "#{runtime}/ruby"
  SSHKit.config.command_map[:bundle] = bundle
  fetch(:bundle_bins).each do |command|
    SSHKit.config.command_map.prefix[command.to_sym].map! { |prefix| prefix == "bundle exec" ? "#{bundle} exec" : prefix }
  end
  set :bundle_path, "/var/www/muzeum/shared/bundle/ruby-3.4.13"
  bundle_environment = { "BUNDLE_IGNORE_CONFIG" => "1", "BUNDLE_FROZEN" => "true",
                         "BUNDLE_WITHOUT" => fetch(:bundle_without) }
  environment = fetch(:default_env).merge(bundle_environment).merge("PATH" => "#{runtime}:/usr/bin:/bin",
    "BUNDLE_PATH" => fetch(:bundle_path), "RBENV_VERSION" => "3.4.13")
  set :default_env, environment
  SSHKit.config.default_env = environment
  set :bundle_env_variables, bundle_environment
end

def muzeum_probe_release_runtime(directory, revision)
  on primary(:app) do
    within directory do
      raise "Runtime probe checkout revision mismatch" unless capture(:cat, "REVISION") == revision

      with fetch(:bundle_env_variables) do
        execute :ruby, "-e", %q('abort "Expected Ruby 3.4.13" unless RUBY_VERSION == "3.4.13"; puts RUBY_DESCRIPTION')
        execute :bundle, "--version"
        execute :bundle, "check"
      end
    end
  end
end

def muzeum_verify_helper
  on primary(:app) do
    installed = capture(:sudo, "-n", "/usr/local/sbin/muzeum-deploy", "version").strip
    expected = Digest::SHA256.hexdigest(File.binread(File.expand_path("../ops/deploy/muzeum_deploy.py", __dir__)) + File.binread(File.expand_path("../ops/deploy/inspect.rb", __dir__)) + File.binread(File.expand_path("../ops/runtime/muzeum_runtime.py", __dir__)))
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
  desc "Verify the exact local revision and installed production readiness without deploying"
  task :preflight do
    approval = MuzeumDeploymentRevision.resolve!
    puts "Preflight revision #{approval.fetch(:sha)}; CI #{approval.fetch(:ci)}"
    muzeum_verify_helper
    on primary(:app) do
      execute :sudo, "-n", "/usr/local/sbin/muzeum-deploy", "preflight"
    end
  end

  desc "Verify the reviewed release checkout and live production baseline without deploying"
  task :release_preflight, [ :version, :checkout, :runtime_probe ] do |_, args|
    approval = MuzeumDeploymentRevision.resolve_release!(args[:version], args[:checkout])
    puts "Preflight #{approval.fetch(:branch)} at #{approval.fetch(:sha)}; CI #{approval.fetch(:ci)}"
    muzeum_verify_helper
    if approval.fetch(:sha) == MuzeumDeploymentRevision::V034_SHA
      directory = args[:runtime_probe].to_s
      raise "Provide the unpublished release checkout for the runtime probe" unless %r{\A/var/www/muzeum/releases/[0-9]{14}\z}.match?(directory)

      muzeum_configure_release_runtime
      muzeum_probe_release_runtime(directory, approval.fetch(:sha))
    end
    on primary(:app) do
      execute :sudo, "-n", "/usr/local/sbin/muzeum-deploy", "release-preflight", approval.fetch(:baseline), approval.fetch(:sha)
    end
  end

  desc "Deploy an explicitly reviewed release checkout through the guarded workflow"
  task :release_deploy, [ :version, :checkout ] do |_, args|
    set :muzeum_release_selection, [ args[:version], args[:checkout] ]
    Rake::Task["deploy"].invoke
  end

  desc "Synchronize a published tag with the live SHA without deploying or restarting"
  task :sync_release, [ :tag ] do |_, args|
    tag = args.fetch(:tag).to_s
    current = File.join(fetch(:deploy_to), "current")
    on primary(:app) do
      revision = capture(:cat, File.join(current, "REVISION"))
      MuzeumPublishedRelease.verify!(revision, tag:, command: MuzeumDeploymentRevision.method(:command))
      ruby = revision == MuzeumDeploymentRevision::V034_SHA ? "/opt/muzeum/ruby-3.4.13/bin/ruby" : "/home/muzeum/.rbenv/shims/ruby"
      execute ruby, File.join(current, "lib/muzeum_published_release.rb"), revision, tag
      puts "Synchronized Muzeum #{tag} for live revision #{revision}"
    end
  end

  desc "Retry GitHub reporting from the existing server receipt; never redeploy"
  task :report, [ :token ] do |_task, args|
    token = args.fetch(:token)
    record = muzeum_reporting.read(token)
    muzeum_publish_result(token, record.fetch("sha"))
  end

  task :authorize do
    selection = fetch(:muzeum_release_selection, nil)
    approval = selection ? MuzeumDeploymentRevision.resolve_release!(*selection) : MuzeumDeploymentRevision.resolve!
    if approval.fetch(:sha) == MuzeumDeploymentRevision::V034_SHA
      muzeum_configure_release_runtime
      set :reviewed_release_version, approval.fetch(:version)
    end
    set :approved_revision, approval.fetch(:sha)
    set :branch, approval.fetch(:sha)
    set :deployment_token, SecureRandom.hex(16)
    puts "Muzeum immutable revision #{fetch(:approved_revision)}; CI #{approval.fetch(:ci)}"
    command = ENV.fetch("APPLICATION_SHELL_PREFLIGHT", "application-shell-preflight")
    review = ENV.fetch("APPLICATION_SHELL_REVIEW") do
      raise "Set APPLICATION_SHELL_REVIEW to the exact candidate Application Shell review"
    end
    unless system(command, "--app", "muzeum", "--revision", fetch(:approved_revision), "--review", review)
      raise "Application Shell preflight failed. Resolve the reported checks before retrying."
    end
    outbox = muzeum_reporting
    outbox.check_clear!
    muzeum_verify_helper
    on primary(:app) do
      if selection
        execute :sudo, "-n", "/usr/local/sbin/muzeum-deploy", "begin-release", fetch(:approved_revision),
          fetch(:deployment_token), *approval.values_at(:branch, :version, :baseline, :scope, :ci)
      else
        execute :sudo, "-n", "/usr/local/sbin/muzeum-deploy", "begin", fetch(:approved_revision), fetch(:deployment_token)
      end
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

  task :probe_release_runtime do
    revision = fetch(:approved_revision)
    muzeum_probe_release_runtime(release_path, revision) if revision == MuzeumDeploymentRevision::V034_SHA
  end

  task :prepare do
    on primary(:app) do
      if (version = fetch(:reviewed_release_version, nil))
        revision = fetch(:approved_revision)
        raise "Unexpected reviewed release metadata" unless version == "v0.3.4" &&
          revision == MuzeumDeploymentRevision::V034_SHA && capture(:cat, release_path.join("REVISION")) == revision

        upload! StringIO.new("#{revision} #{version}\n"), release_path.join("REVIEWED_RELEASE")
      end
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
before "bundler:config", "muzeum:probe_release_runtime"
after "deploy:updated", "muzeum:prepare"
after "deploy:published", "muzeum:finish"
after "deploy:finished", "muzeum:complete"
after "deploy:failed", "muzeum:failed"

at_exit do
  if fetch(:deployment_reporting_started, false) && !fetch(:deployment_reporting_finalized, false)
    muzeum_publish_result(fetch(:deployment_token), fetch(:approved_revision))
  end
end
