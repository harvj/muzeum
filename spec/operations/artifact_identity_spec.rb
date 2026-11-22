require "spec_helper"
require "tmpdir"
require "pathname"
require_relative "../../lib/muzeum_artifact_identity"

RSpec.describe MuzeumArtifactIdentity do
  it "renders a boot-pinned candidate, refreshes its exact publication locally, and keeps rollback identity separate" do
    records = JSON.parse(File.read("spec/fixtures/files/application_shell/v2.json")).dig("release_identity", "records")
    %w[rc1 rc2 prior_rc].each { |key| records.fetch(key)["application"] = "muzeum" }
    %w[final conflict chronology_error prior_final bad_label].each { |key| records.fetch(key).fetch("candidate")["application"] = "muzeum" }
    Dir.mktmpdir do |temporary|
      root = Pathname(temporary)
      release = root.join("release").tap(&:mkdir)
      receipts = root.join("receipts").tap(&:mkdir)
      identity = release.join("ARTIFACT_IDENTITY.json")
      identity.write(records.fetch("bad_label").to_json)
      revision = records.fetch("rc2").fetch("source_sha")
      expect(described_class.boot(release, revision:, receipts:)).to be_nil

      rc2 = records.fetch("rc2")
      rc1 = records.fetch("rc1")
      identity.write(rc2.to_json)
      running = described_class.boot(release, revision:, receipts:)
      expect(running.label).to eq("v0.26.0-rc.2")
      receipt = receipts.join("#{Digest::SHA256.hexdigest(rc2.sort.to_h.to_json)}.json")
      %w[chronology_error bad_label].each do |name|
        receipt.write(records.fetch(name).to_json)
        expect(running.label).to eq("v0.26.0-rc.2")
      end
      receipt.write(records.fetch("final").to_json)
      expect(running.label).to eq("v0.26.0")
      expect(described_class.boot(release, revision:, receipts:).label).to eq("v0.26.0")

      receipt.write(records.fetch("conflict").to_json)
      expect(running.label).to eq("v0.26.0")
      receipt.write(records.fetch("final").to_json)

      identity.write(rc1.to_json)
      rollback = described_class.boot(release, revision:, receipts:)
      expect(rollback.label).to eq("v0.26.0-rc.1")
      expect(running.label).to eq("v0.26.0")

      prior_rc = records.fetch("prior_rc")
      identity.write(prior_rc.to_json)
      receipts.join("#{Digest::SHA256.hexdigest(prior_rc.sort.to_h.to_json)}.json").write(records.fetch("prior_final").to_json)
      expect(described_class.boot(release, revision: prior_rc.fetch("source_sha"), receipts:).label).to eq("v0.25.0")
    end
  end
end
