require Rails.root.join("lib/muzeum_published_release")

Rails.application.config.x.published_release_path = nil
Rails.application.config.x.running_revision = nil

# Pin the running process to its own immutable release, even if current later moves.
if Rails.env.production?
  release = Rails.root.realpath
  Rails.application.config.x.running_revision = MuzeumPublishedRelease.revision(release)
  Rails.application.config.x.published_release_path = release.parent.parent.join("shared", MuzeumPublishedRelease::FILENAME)
end
