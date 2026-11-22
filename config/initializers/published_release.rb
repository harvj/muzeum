require Rails.root.join("lib/muzeum_published_release")
require Rails.root.join("lib/muzeum_artifact_identity")

Rails.application.config.x.published_release_path = nil
Rails.application.config.x.reviewed_release_path = nil
Rails.application.config.x.running_revision = nil
Rails.application.config.x.artifact_identity = nil
Rails.application.config.x.artifact_identity_present = false
Rails.application.config.x.development_version = nil

# Pin the running process to its own immutable release, even if current later moves.
if Rails.env.production?
  release = Rails.root.realpath
  Rails.application.config.x.running_revision = MuzeumPublishedRelease.revision(release)
  Rails.application.config.x.artifact_identity_present = release.join("ARTIFACT_IDENTITY.json").exist?
  Rails.application.config.x.artifact_identity = MuzeumArtifactIdentity.boot(release,
    revision: Rails.application.config.x.running_revision, receipts: release.parent.parent.join("shared", "release-publications"))
  Rails.application.config.x.reviewed_release_path = release.join("REVIEWED_RELEASE")
  Rails.application.config.x.published_release_path = release.parent.parent.join("shared", MuzeumPublishedRelease::FILENAME)
elsif Rails.env.development?
  Rails.application.config.x.development_version = "v#{Rails.root.join("VERSION").read.strip}-dev"
end
