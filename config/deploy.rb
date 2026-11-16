lock "~> 3.20"
set :application, "muzeum"
set :repo_url, "git@github.com:harvj/muzeum.git"
set :deploy_to, "/var/www/muzeum"
set :branch, ENV["APPROVED_SHA"]
set :keep_releases, 5
set :bundle_flags, "--quiet"
append :linked_files, ".env"
append :linked_dirs, "storage", "log", "tmp/pids", "tmp/sockets"
set :default_env, { "RAILS_ENV" => "production", "RBENV_VERSION" => "3.4.12" }
set :bundle_version, 4
set :bundle_jobs, 2
SSHKit.config.command_map[:bundle] = "/home/muzeum/.rbenv/shims/bundle"
set :assets_prefix, "assets"
set :assets_manifests, [ "public/assets/.manifest.json" ]
set :rails_env, "production"
set :assets_roles, [ :web ]
set :default_env, fetch(:default_env).merge("PATH" => "/home/muzeum/.rbenv/shims:/home/muzeum/.rbenv/bin:$PATH", "SECRET_KEY_BASE_DUMMY" => "1")
set :ssh_options, { forward_agent: false, verify_host_key: :always }

namespace :muzeum do
  task :authorize do
    abort "Explicit approval required: APPROVAL_REF and full APPROVED_SHA" unless
      ENV["APPROVAL_REF"].to_s.match?(/\S/) && ENV["APPROVED_SHA"].to_s.match?(/\A[0-9a-f]{40}\z/)
    abort "Server provisioning/runtime/backup review is not complete" unless ENV["INFRASTRUCTURE_READY"] == "yes"
  end

  desc "Migrate the prepared release only with explicit migration and backup approval"
  task :migrate do
    invoke "muzeum:authorize"
    abort "Explicit migration/backup approval required" unless ENV["MIGRATION_APPROVAL_REF"].to_s.match?(/\S/) && ENV["BACKUP_ID"].to_s.match?(/\S/)
    invoke "muzeum:verify_release"
    on primary(:app) do
      within release_path do
        # shared .env.migrate is shell-compatible; never echo it or pass secrets in argv.
        execute "set -ae; . #{shared_path}/.env.migrate; set +a; cd #{release_path} && /home/muzeum/.rbenv/shims/bundle exec rails db:migrate"
      end
    end
  end

  task :verify_release do
    on roles(:app) do
      execute :test, "$(cat #{release_path}/REVISION)", "=", ENV.fetch("APPROVED_SHA")
    end
  end

  task :restart do
    on roles(:app) do
      execute :sudo, "-n", :systemctl, :restart, "muzeum-web.service", "muzeum-worker.service"
    end
  end

  task :verify do
    on roles(:app) do
      execute :test, "$(cat #{current_path}/REVISION)", "=", ENV.fetch("APPROVED_SHA")
      execute :systemctl, "is-active", "muzeum-web.service", "muzeum-worker.service"
      execute "test $(curl --fail --silent --show-error --output /dev/null --write-out '%{http_code}' -H 'Host: muzeum.fm' -H 'X-Forwarded-Proto: https' http://127.0.0.1:3011/up) = 200"
    end
  end
end
before "deploy:starting", "muzeum:authorize"
before "deploy:reverting", "muzeum:authorize"
before "deploy:publishing", "muzeum:verify_release"
after "deploy:updated", "muzeum:migrate"
after "deploy:published", "muzeum:restart"
after "deploy:finished", "muzeum:verify"
after "deploy:finishing_rollback", "muzeum:verify"
