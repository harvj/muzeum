require "shellwords"
require_relative "../../../lib/muzeum_deployment_revision"
require_relative "../../../lib/muzeum_published_release"

lock "~> 3.20"
set :application, "muzeum"
set :repo_url, "git@github.com:harvj/muzeum.git"
set :deploy_to, "/var/www/muzeum"
set :rails_env, "production"
set :assets_roles, [ :web ]
set :assets_manifests, [ "public/assets/.manifest.json" ]
append :linked_files, ".env"
append :linked_dirs, "storage", "log", "tmp/pids", "tmp/sockets"
set :bundle_path, "/var/www/muzeum/shared/bundle/ruby-3.4.13"
set :bundle_env_variables, { BUNDLE_FROZEN: "true" }
set :ssh_options, { forward_agent: false, verify_host_key: :always, auth_methods: %w[publickey], non_interactive: true }

runtime = "/opt/muzeum/ruby-3.4.13/bin"
set :default_env, { "PATH" => "#{runtime}:/usr/bin:/bin", "SECRET_KEY_BASE_DUMMY" => "1" }
SSHKit.config.command_map[:ruby] = "#{runtime}/ruby"
bundle = "#{runtime}/ruby #{runtime}/bundle"
SSHKit.config.command_map[:bundle] = bundle
Rake::Task["bundler:map_bins"].enhance do
  fetch(:bundle_bins).each do |bin|
    SSHKit.config.command_map.prefix[bin.to_sym].map! { |prefix| prefix == "bundle exec" ? "#{bundle} exec" : prefix }
  end
end

def verify_muzeum_tree(revision)
  script = <<~SH
    set -eu
    index=$(mktemp -d)
    trap 'rm -rf -- "$index"' EXIT
    export GIT_INDEX_FILE="$index/index"
    git --no-replace-objects --git-dir="$1" --work-tree="$2" read-tree "$3"
    for link in .env storage log tmp/pids tmp/sockets public/assets; do
      test "$(readlink "$2/$link")" = "$4/$link"
    done
    # These tracked empty-directory sentinels are replaced by Capistrano links.
    git --no-replace-objects --git-dir="$1" --work-tree="$2" update-index --skip-worktree \
      -- log/.keep storage/.keep tmp/pids/.keep
    git --no-replace-objects --git-dir="$1" --work-tree="$2" update-index --refresh
    git --no-replace-objects --git-dir="$1" --work-tree="$2" diff-index --exit-code "$3" --
  SH
  execute :bash, "-c", Shellwords.escape(script), "verify-tree",
    repo_path.to_s.shellescape, release_path.to_s.shellescape, revision, shared_path.to_s.shellescape
end

namespace :muzeum do
  task :pin do
    sha, baseline, branch, checkout = ENV.values_at("MUZEUM_REVISION", "MUZEUM_BASELINE", "MUZEUM_BRANCH", "MUZEUM_CHECKOUT")
    guard = MuzeumDeploymentRevision
    raise "Use exact candidate and baseline commits" unless [ sha, baseline ].all? { |value| guard::SHA.match?(value.to_s) }
    raise "Use main or a versioned release branch" unless branch == "main" ||
      (branch&.start_with?("release/") && guard::VERSION.match?(branch.delete_prefix("release/")))

    Dir.chdir(File.realpath(checkout)) do
      raise "Checkout differs from approved revision" unless guard.checkout!(branch) == sha

      guard.command("git", "merge-base", "--is-ancestor", baseline, sha)
      puts "Exact release CI #{guard.ci!(sha, branch:, required_jobs: true)}"
      raise "Application Shell review failed" unless system("application-shell-preflight", "--app", "muzeum",
        "--revision", sha, "--review", ENV.fetch("APPLICATION_SHELL_REVIEW"))
    end
    on primary(:app) do
      raise "Running baseline changed" unless capture(:cat, current_path.join("REVISION")) == baseline
    end
    set :branch, sha
  end

  desc "Stage an approved Git commit without switching the active release"
  task stage: %w[muzeum:pin deploy:starting deploy:started deploy:updating deploy:updated] do
    on primary(:app) do
      raise "Staged revision mismatch" unless capture(:cat, release_path.join("REVISION")) == fetch(:branch)
      verify_muzeum_tree(fetch(:branch))

      puts "Staged #{fetch(:branch)} at #{release_path}"
    end
  end

  desc "Publish the verified candidate or restore the explicitly reviewed prior artifact"
  task :select do
    timestamp, revision, current = ENV.values_at("MUZEUM_STAGED_RELEASE", "MUZEUM_REVISION", "MUZEUM_BASELINE")
    raise "Use exact release identities" unless /\A[0-9]{14}\z/.match?(timestamp.to_s) &&
      [ revision, current ].all? { |sha| MuzeumDeploymentRevision::SHA.match?(sha.to_s) }

    set :release_path, releases_path.join(timestamp)
    on primary(:app) do
      raise "Unexpected running release" unless capture(:cat, current_path.join("REVISION")) == current
      raise "Staged revision mismatch" unless capture(:cat, release_path.join("REVISION")) == revision
      verify_muzeum_tree(revision)
    end
    invoke "deploy:publishing"
    invoke "deploy:published"
  end

  desc "Synchronize the published GitHub tag with the exact running revision"
  task :sync_release, [ :tag ] do |_, args|
    tag = args.fetch(:tag).to_s
    on primary(:app) do
      revision = capture(:cat, current_path.join("REVISION"))
      MuzeumPublishedRelease.verify!(revision, tag:, command: MuzeumDeploymentRevision.method(:command))
      execute :ruby, current_path.join("lib/muzeum_published_release.rb"), revision, tag
    end
  end

  task :operator_required do
    abort "Use muzeum:stage and the reviewed Muzeum maintenance runbook"
  end
end

before "deploy:rollback", "muzeum:operator_required"
before "deploy", "muzeum:operator_required"
