require "spec_helper"
require_relative "../../lib/muzeum_release_package"

RSpec.describe MuzeumReleasePackage do
  it "binds the actual built assets and files while excluding mutable linked runtime data" do
    Dir.mktmpdir do |directory|
      root = Pathname(directory)
      shared = root.join("shared").tap(&:mkdir)
      shared.join("release-candidates").mkdir
      environment = shared.join(".env").tap { |path| path.write("secret") }
      release = root.join("release").tap(&:mkdir)
      assets = release.join("public/assets").tap(&:mkpath)
      assets.join(".manifest.json").write('{"application.css":"application-1.css"}')
      css = assets.join("application-1.css").tap { |path| path.write("body {}") }
      revision = "1" * 40
      release.join("REVISION").write(revision)
      release.join(".env").make_symlink(environment)

      identity = described_class.record!(release, shared:, revision:, version: "0.6.1")
      expect(identity.fetch("candidate_number")).to eq(1)
      environment.write("rotated")
      expect(described_class.record!(release, shared:, revision:, version: "0.6.1")).to eq(identity)

      css.write("body { display: none }")
      expect(described_class.digest(release, shared:)).not_to eq(identity.fetch("artifact_sha256"))
      expect { described_class.record!(release, shared:, revision:, version: "0.6.1") }
        .to raise_error("Candidate identity has already been bound")
    end
  end

  it "refuses to digest a package with mutable shared compiled assets" do
    Dir.mktmpdir do |directory|
      root = Pathname(directory)
      shared = root.join("shared").tap(&:mkdir)
      release = root.join("release").tap(&:mkdir)
      release.join("public").mkdir
      release.join("public/assets").make_symlink(shared.join("public/assets"))

      expect { described_class.digest(release, shared:) }.to raise_error("Unexpected release symlink: public/assets")
    end
  end
end
