require "shellwords"
require "securerandom"
require_relative "../../../lib/muzeum_deployment_revision"
require_relative "../../../lib/muzeum_release_identity_tasks"
require_relative "../../../lib/muzeum_deployment_reporting"
require_relative "../../../lib/muzeum_shell_preflight"
include MuzeumReleaseIdentityTasks

lock "~> 3.20"
set :application, "muzeum"
set :repo_url, "git@github.com:harvj/muzeum.git"
set :deploy_to, "/var/www/muzeum"
set :rails_env, "production"
set :assets_roles, [ :web ]
set :assets_manifests, [ "public/assets/.manifest.json" ]
append :linked_files, ".env"
append :linked_dirs, "storage", "log", "tmp"
before "deploy:symlink:linked_dirs", "muzeum:shared_runtime"
set :bundle_path, "/var/www/muzeum/shared/bundle/ruby-3.4.13"
set :bundle_env_variables, { BUNDLE_FROZEN: "true" }
set :ssh_options, { forward_agent: false, verify_host_key: :always, auth_methods: %w[publickey], non_interactive: true }

runtime = "/opt/muzeum/ruby-3.4.13/bin"
set :default_env, { "PATH" => "#{runtime}:/usr/bin:/bin", "SECRET_KEY_BASE_DUMMY" => "1", "DISABLE_BOOTSNAP" => "1" }
SSHKit.config.command_map[:ruby] = "#{runtime}/ruby"
bundle = "#{runtime}/ruby #{runtime}/bundle"
SSHKit.config.command_map[:bundle] = bundle
Rake::Task["bundler:map_bins"].enhance do
  fetch(:bundle_bins).each do |bin|
    SSHKit.config.command_map.prefix[bin.to_sym].map! { |prefix| prefix == "bundle exec" ? "#{bundle} exec" : prefix }
  end
  # Apply this at the process boundary for the bundled rake invocation.
  rake_prefix = SSHKit.config.command_map.prefix[:rake]
  bootsnap_env = "/usr/bin/env DISABLE_BOOTSNAP=1"
  rake_prefix.unshift(bootsnap_env) unless rake_prefix.include?(bootsnap_env)
end

# Capistrano Rails normally links public/assets across releases.
Rake::Task["deploy:set_linked_dirs"].clear_actions

def verify_muzeum_assets
  path = release_path.join("public/assets")
  execute :ruby, "-rjson", "-rpathname", "-e", Shellwords.escape(<<~RUBY), path.to_s.shellescape
    assets = Pathname(ARGV.fetch(0))
    manifest = assets.join(".manifest.json")
    abort "Assets and manifest must be release-local" unless assets.directory? &&
      assets.realpath == assets && manifest.file? && !manifest.symlink?
    entries = JSON.parse(manifest.read)
    abort "Asset manifest missing application entry points" unless %w[application.css application.js].all? { |key| entries.key?(key) }
    if assets.join("../../app/javascript/controllers/guide_controller.js").file?
      abort "Guide controller missing from manifest" unless entries.key?("controllers/guide_controller.js")
    end
    entries.each_value do |entry|
      relative = Pathname(entry.is_a?(Hash) ? entry.fetch("digested_path") : entry)
      file = assets.join(relative)
      abort "Invalid compiled asset: \#{relative}" unless file.file? && !file.symlink? &&
        file.realpath.to_s.start_with?(assets.to_s + "/") && file.size.positive?
    end
  RUBY
end

def verify_muzeum_tree(revision)
  script = <<~SH
    set -eu
    index=$(mktemp -d)
    trap 'rm -rf -- "$index"' EXIT
    export GIT_INDEX_FILE="$index/index"
    git --no-replace-objects --git-dir="$1" --work-tree="$2" read-tree "$3"
    for link in .env storage log tmp; do
      test "$(readlink "$2/$link")" = "$4/$link"
    done
    # These tracked empty-directory sentinels are replaced by Capistrano links.
    git --no-replace-objects --git-dir="$1" --work-tree="$2" update-index --skip-worktree \
      -- log/.keep storage/.keep tmp/.keep tmp/pids/.keep tmp/storage/.keep
    git --no-replace-objects --git-dir="$1" --work-tree="$2" update-index --refresh
    git --no-replace-objects --git-dir="$1" --work-tree="$2" diff-index --exit-code "$3" --
  SH
  execute :bash, "-c", Shellwords.escape(script), "verify-tree",
    repo_path.to_s.shellescape, release_path.to_s.shellescape, revision, shared_path.to_s.shellescape
end

namespace :muzeum do
  task :shared_runtime do
    on roles(:app) do
      execute :mkdir, "-p", shared_path.join("tmp/pids"), shared_path.join("tmp/sockets"), shared_path.join("tmp/storage")
    end
  end

  task :pin do
    sha, baseline, branch, checkout = ENV.values_at("MUZEUM_REVISION", "MUZEUM_BASELINE", "MUZEUM_BRANCH", "MUZEUM_CHECKOUT")
    guard = MuzeumDeploymentRevision
    raise "Use exact candidate and baseline commits" unless [ sha, baseline ].all? { |value| guard::SHA.match?(value.to_s) }
    raise "Use main or a versioned release branch" unless branch == "main" ||
      (branch&.start_with?("release/") && guard::VERSION.match?(branch.delete_prefix("release/")))

    Dir.chdir(File.realpath(checkout)) do
      raise "Checkout differs from approved revision" unless guard.checkout!(branch) == sha

      source_baseline = ENV.fetch("MUZEUM_SOURCE_BASELINE", baseline)
      raise "Invalid source baseline" unless guard::SHA.match?(source_baseline)
      guard.command("git", "merge-base", "--is-ancestor", source_baseline, baseline)
      guard.command("git", "merge-base", "--is-ancestor", source_baseline, sha)
      puts "Exact release CI #{guard.ci!(sha, branch:, required_jobs: true)}"
      MuzeumShellPreflight.verify!(sha)
    end
    on primary(:app) do
      raise "Running baseline changed" unless capture(:cat, current_path.join("REVISION")) == baseline
    end
    set :branch, sha
  end

  def muzeum_outbox
    directory = Dir.chdir(File.realpath(ENV.fetch("MUZEUM_CHECKOUT"))) do
      MuzeumDeploymentRevision.command("git", "rev-parse", "--path-format=absolute", "--git-common-dir")
    end
    MuzeumDeploymentReporting::Outbox.new(File.join(directory, "muzeum-deployments"))
  end

  def muzeum_report(token, revision)
    host = fetch(:muzeum_operator_host)
    remote = Shellwords.join(["/usr/bin/sudo", "-n", "/usr/local/sbin/muzeum-deploy", "receipt", revision, token])
    receipt = JSON.parse(MuzeumDeploymentRevision.command("ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "--", host, remote))
    result = muzeum_outbox.reconcile(token, receipt)
    puts "GitHub deployment #{result.fetch(:id)}: #{result.fetch(:state)}"
  rescue StandardError
    warn "GitHub reporting pending. Retry: cap production 'muzeum:report[#{token}]'"
  end

  task :report, [:token] do |_, args|
    token = args.fetch(:token)
    muzeum_report(token, muzeum_outbox.read(token).fetch("sha"))
  end

  # Staging SSH runs as the app UID. Only the existing operator SSH profile
  # can invoke the installed protected phase helper.
  def muzeum_phase(*arguments)
    host = fetch(:muzeum_operator_host)
    remote = Shellwords.join(["/usr/bin/sudo", "-n", "/usr/local/sbin/muzeum-deploy", *arguments])
    ok = system("ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "--", host, remote)
    raise "Muzeum deployment phase failed: #{arguments.first}" unless ok
  end

  def muzeum_check_target(revision)
    on primary(:app) do
      raise "Staged revision mismatch" unless capture(:cat, release_path.join("REVISION")) == revision
      verify_muzeum_tree(revision)
      verify_muzeum_assets
    end
  end

  def muzeum_run_release(rollback:)
    revision = fetch(:branch)
    baseline = ENV.fetch("MUZEUM_BASELINE")
    timestamp = ENV["MUZEUM_STAGED_RELEASE"]
    if rollback || timestamp
      raise "Use an exact retained release directory" unless /\A[0-9]{14}\z/.match?(timestamp.to_s)
      set :release_path, releases_path.join(timestamp)
      muzeum_check_target(revision)
    end

    ruby = SSHKit.config.command_map[:ruby]
    outbox = muzeum_outbox
    outbox.check_clear!
    token = SecureRandom.hex(16)
    muzeum_phase(rollback ? "begin-rollback" : "begin-operator", revision, token, baseline)
    begin
      outbox.create(revision, token)
      reporting_started = true
      outbox.start(token)
      outbox.attempted(token)
      unless timestamp
        %w[deploy:starting deploy:started deploy:updating deploy:updated].each { |task| invoke task }
      end
      muzeum_check_target(revision)
      candidate = nil
      on primary(:app) do
        candidate = if timestamp
          muzeum_verify_artifact(release_path, revision, ruby:)
        else
          version = capture(:cat, release_path.join("VERSION"))
          muzeum_package_identity(release_path, revision, version, ruby:)
        end
      end
      outbox.bind_artifact(token, candidate)
      muzeum_phase("prepare", revision, token, release_path.to_s)
      muzeum_check_target(revision)
      invoke "deploy:publishing"
      invoke "deploy:published"
      muzeum_phase("finish", revision, token)
      on primary(:app) do
        unless capture(:readlink, "-f", current_path) == release_path.to_s &&
            muzeum_verify_artifact(release_path, revision, ruby:) == candidate
          raise "Running artifact differs from the verified package"
        end
      end
      muzeum_phase("complete", revision, token)
    rescue StandardError, Interrupt
      begin
        muzeum_phase("fail", revision, token)
      rescue StandardError, Interrupt
        warn "Inspect the protected Muzeum phase record for #{token}"
      end
      raise
    ensure
      muzeum_report(token, revision) if reporting_started
    end
  end

  task release: :pin do
    muzeum_run_release(rollback: false)
  end

  task restore: :pin do
    muzeum_run_release(rollback: true)
  end

  desc "Synchronize publication for the exact running Muzeum artifact"
  task :sync_release, [:tag, :deployment, :status] do |_, args|
    on primary(:app) do
      muzeum_sync_release(args.fetch(:tag), deployment: args[:deployment], status: args[:status],
        ruby: SSHKit.config.command_map[:ruby], command: MuzeumDeploymentRevision.method(:command))
    end
  end

end

# Replace the stock task bodies and prerequisites. Standalone partial tasks
# are kept private to the two complete Capistrano entry points.
Rake::Task["deploy"].clear
desc "Deploy one exact approved Muzeum release"
task deploy: "muzeum:release"

Rake::Task["deploy:rollback"].clear
desc "Restore one exact approved Muzeum release without migrations"
task "deploy:rollback" => "muzeum:restore"

alias verify_retained_release muzeum_verify_artifact
def muzeum_verify_artifact(artifact, revision, ruby:)
  identity = verify_retained_release(artifact, revision, ruby:)
  qualified = JSON.parse(File.read(ENV.fetch("MUZEUM_QUALIFIED_ARTIFACT")))
  raise "Retained release differs from the authorized artifact" unless identity == qualified
  identity
end
