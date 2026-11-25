require "spec_helper"
require_relative "../../lib/muzeum_release_package"

RSpec.describe MuzeumReleasePackage do
  it "binds the actual built assets and files while excluding mutable linked runtime data" do
    Dir.mktmpdir do |directory|
      root = Pathname(directory)
      shared = root.join("shared").tap(&:mkdir)
      shared.join("release-candidates").mkdir
      environment = shared.join(".env").tap { |path| path.write("secret") }
      runtime = shared.join("tmp").tap(&:mkdir)
      release = root.join("release").tap(&:mkdir)
      linked_runtime(release, shared)
      assets = release.join("public/assets").tap(&:mkpath)
      assets.join(".manifest.json").write('{"application.css":"application-1.css"}')
      css = assets.join("application-1.css").tap { |path| path.write("body {}") }
      revision = "1" * 40
      release.join("VERSION").write("0.7.1\n")
      release.join("REVISION").write(revision)
      release.join("REVISION_TIME").write("1795574382\n")
      release.join(".bundle").mkdir
      release.join(".bundle/config").write("---\nBUNDLE_DEPLOYMENT: true\n")
      release.join("assets_manifest_backup").mkdir
      release.join("assets_manifest_backup/.manifest.json").write(assets.join(".manifest.json").read)

      revision_time = release.join("REVISION_TIME")
      revision_time.unlink
      expect { described_class.record!(release, shared:, revision:, version: "0.7.1") }
        .to raise_error("Missing or invalid staged file: REVISION_TIME")
      revision_time.write("1795574382\n")

      identity = described_class.record!(release, shared:, revision:, version: "0.7.1")
      expect(identity.fetch("candidate_number")).to eq(1)
      environment.write("rotated")
      runtime.join("cache/bootsnap").mkpath
      runtime.join("cache/bootsnap/load-path-cache").write("runtime cache")
      runtime.join("restart.txt").write("restart request")
      expect(described_class.record!(release, shared:, revision:, version: "0.7.1")).to eq(identity)

      release.join(".env").unlink
      expect { described_class.digest(release, shared:) }.to raise_error("Release .env must link to the application shared runtime path")
      release.join(".env").make_symlink(environment)

      css.write("body { display: none }")
      expect(described_class.digest(release, shared:)).not_to eq(identity.fetch("artifact_sha256"))
      expect { described_class.record!(release, shared:, revision:, version: "0.7.1") }
        .to raise_error("Candidate identity has already been bound")
    end
  end

  it "refuses a release-local tmp directory or a link to any other target" do
    Dir.mktmpdir do |directory|
      root = Pathname(directory)
      release = root.join("release").tap(&:mkdir)
      shared = root.join("shared").tap(&:mkdir)
      linked_runtime(release, shared)
      release.join("tmp").unlink
      temporary = release.join("tmp").tap(&:mkdir)
      expect { described_class.digest(release, shared:) }
        .to raise_error("Release tmp must link to the application shared runtime path")

      temporary.rmdir
      temporary.make_symlink(root.join("other"))
      expect { described_class.digest(release, shared:) }
        .to raise_error("Release tmp must link to the application shared runtime path")
    end
  end

  it "refuses to digest a package with mutable shared compiled assets" do
    Dir.mktmpdir do |directory|
      root = Pathname(directory)
      shared = root.join("shared").tap(&:mkdir)
      release = root.join("release").tap(&:mkdir)
      linked_runtime(release, shared)
      release.join("public").mkdir
      release.join("public/assets").make_symlink(shared.join("public/assets"))

      expect { described_class.digest(release, shared:) }.to raise_error("Unexpected release symlink: public/assets")
    end
  end

  def linked_runtime(release, shared)
    described_class::RUNTIME_LINKS.each do |name|
      release.join(name).make_symlink(shared.join(name))
    end
  end
end
