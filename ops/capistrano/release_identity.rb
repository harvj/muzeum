require_relative "../../lib/muzeum_release_package"
require_relative "../../lib/muzeum_publication_receipt"

# Invoked with the existing Capistrano SSH deployment identity.
if $PROGRAM_NAME == __FILE__
  action, *arguments = ARGV
  release = Pathname(__FILE__).realpath.dirname.parent.parent
  shared = release.parent.parent.join("shared")
  case action
  when "package"
    version, revision = arguments
    puts JSON.generate(MuzeumReleasePackage.record!(release, shared:, version:, revision:))
  when "verify"
    revision, = arguments
    candidate = MuzeumArtifactIdentity.read(release.join(MuzeumReleasePackage::IDENTITY))
    unless candidate&.fetch("source_sha") == revision &&
        candidate.fetch("artifact_sha256") == MuzeumReleasePackage.digest(release, shared:)
      abort "Staged artifact differs from its candidate identity"
    end
    puts JSON.generate(candidate)
  when "receipt"
    receipt = JSON.parse(STDIN.read(8193), allow_duplicate_key: false)
    candidate = MuzeumArtifactIdentity.read(release.join(MuzeumReleasePackage::IDENTITY))
    unless receipt.keys.sort == MuzeumArtifactIdentity::PUBLICATION_KEYS &&
        candidate && candidate == receipt.fetch("candidate") &&
        candidate.fetch("artifact_sha256") == MuzeumReleasePackage.digest(release, shared:)
      abort "Publication receipt does not match the retained artifact"
    end
    MuzeumPublicationReceipt.write!(shared.join("release-publications"), receipt)
  else
    abort "Expected package, verify, or receipt"
  end
end
