# Copy into the reviewed operator checkout as config/deploy/disposable.rb.
# Run in an isolated Linux environment with no production mounts or credentials.
require "pathname"

root = Pathname(ENV.fetch("MUZEUM_DISPOSABLE_ROOT")).realpath
repo = Pathname(ENV.fetch("MUZEUM_DISPOSABLE_REPO")).realpath
revision = ENV.fetch("MUZEUM_DISPOSABLE_REVISION")
abort "Expected a disposable Linux Capistrano host" unless RUBY_PLATFORM.include?("linux") &&
  root.to_s == "/var/www/muzeum" && root.join(".muzeum-disposable").file? &&
  !root.join("current").exist? && !root.join("current").symlink?
abort "Expected a local Git repository and an immutable revision" unless repo.directory? &&
  /\A[0-9a-f]{40}\z/.match?(revision)
abort "The reviewed Muzeum operator workflow is required" unless respond_to?(:muzeum_check_target, true)

server "localhost", roles: %w[app web db]
set :deploy_to, root
set :repo_url, repo.to_s
set :branch, revision

namespace :muzeum do
  task :qualify_staging do
    SSHKit.config.backend = SSHKit::Backend::Local
    environment = root.join("shared/.env")
    abort "Expected a private disposable environment file" unless environment.file? &&
      !environment.symlink? && environment.stat.mode & 0o077 == 0

    %w[deploy:starting deploy:started deploy:updating deploy:updated].each { |task| invoke task }
    muzeum_check_target(revision)
    on primary(:app) do
      ruby = SSHKit.config.command_map[:ruby]
      version = capture(:cat, release_path.join("VERSION"))
      candidate = muzeum_package_identity(release_path, revision, version, ruby:)
      identity = root.join("qualified-artifact.json")
      identity.write(JSON.generate(candidate))
      ENV["MUZEUM_QUALIFIED_ARTIFACT"] = identity.to_s
      raise "Staged artifact changed" unless muzeum_verify_artifact(release_path, revision, ruby:) == candidate

      puts JSON.generate(candidate)
    end
  end
end
