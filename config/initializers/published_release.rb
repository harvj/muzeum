require Rails.root.join("lib/muzeum_published_release")

require Rails.root.join("lib/muzeum_artifact_identity")

Rails.application.config.x.release_identity = nil
Rails.application.config.x.development_release_label = nil
Rails.application.config.x.published_release_path = nil
Rails.application.config.x.reviewed_release_path = nil
Rails.application.config.x.running_revision = nil

# Pin the running process to its own immutable release, even if current later moves.
if Rails.env.production?
  release = Rails.root.realpath
  Rails.application.config.x.running_revision = MuzeumPublishedRelease.revision(release)
  shared = release.parent.parent.join("shared")
  revision = Rails.application.config.x.running_revision
  Rails.application.config.x.release_identity = MuzeumArtifactIdentity.boot(release, revision:, receipts: shared.join("release-publications"))
  unless release.join("ARTIFACT_IDENTITY.json").exist? || release.join("ARTIFACT_IDENTITY.json").symlink?
    Rails.application.config.x.reviewed_release_path = release.join("REVIEWED_RELEASE")
    Rails.application.config.x.published_release_path = shared.join(MuzeumPublishedRelease::FILENAME)
  end
elsif Rails.env.development?
  version = Rails.root.join("VERSION").read.strip
  Rails.application.config.x.development_release_label = "v#{version}-dev" if MuzeumArtifactIdentity::VERSION.match?(version)
end
