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
require "digest"
require "securerandom"

namespace :muzeum do
  task :authorize do
    approval = MuzeumDeploymentRevision.resolve!
    set :approved_revision, approval.fetch(:sha)
    set :branch, approval.fetch(:sha)
    set :deployment_token, SecureRandom.hex(16)
    info "Muzeum immutable revision #{fetch(:approved_revision)}; CI #{approval.fetch(:ci)}"
    on primary(:app) do
      installed = capture(:sudo, "-n", "/usr/local/sbin/muzeum-deploy", "version").strip
      expected = Digest::SHA256.hexdigest(File.binread(File.expand_path("../ops/deploy/muzeum_deploy.py", __dir__)) + File.binread(File.expand_path("../ops/deploy/inspect.rb", __dir__)))
      abort "Reviewed deployment helper is not installed; complete separate safety review first" unless installed == expected
      execute :sudo, "-n", "/usr/local/sbin/muzeum-deploy", "begin", fetch(:approved_revision), fetch(:deployment_token)
      set :deployment_lock_acquired, true
    end
  end

  task :prepare do
    on primary(:app) do
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
  end

  task :failed do
    next unless fetch(:deployment_lock_acquired, false)
    on primary(:app) do
      execute :sudo, "-n", "/usr/local/sbin/muzeum-deploy", "fail", fetch(:approved_revision), fetch(:deployment_token)
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
