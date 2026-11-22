require "spec_helper"
require "pathname"
require_relative "../../lib/muzeum_publication_receipt"

RSpec.describe MuzeumPublicationReceipt do
  it "requires matching production acceptance before publication of the exact artifact" do
    candidate = JSON.parse(File.read("spec/fixtures/files/application_shell/v2.json")).dig("release_identity", "records", "rc2")
    candidate["application"] = "muzeum"
    sha = candidate.fetch("source_sha")
    tag = "v#{candidate.fetch('target_version')}"
    raw = JSON.generate(candidate)
    release = { "tag_name" => tag, "draft" => false, "prerelease" => false, "published_at" => "2023-02-01T00:00:00Z",
      "assets" => [{"name" => "muzeum-artifact.json", "id" => 9, "size" => raw.bytesize,
        "digest" => "sha256:#{Digest::SHA256.hexdigest(raw)}"}] }
    deployment = { "sha" => sha, "environment" => "production", "production_environment" => true,
      "payload" => candidate, "creator" => {"login" => "release-operator"} }
    status = { "environment" => "production", "state" => "success", "creator" => {"login" => "release-operator"},
      "created_at" => "2023-01-01T00:00:00Z" }
    command = lambda do |*argv|
      case argv.fetch(2)
      when "repos/harvj/muzeum/deployments/1" then deployment.to_json
      when "repos/harvj/muzeum/deployments/1/statuses/2" then status.to_json
      when "repos/harvj/muzeum/releases/tags/#{tag}" then release.to_json
      when "repos/harvj/muzeum/commits/#{tag}" then sha
      when "repos/harvj/muzeum/releases/assets/9" then raw
      else raise "Unexpected API request"
      end
    end

    Dir.mktmpdir do |temporary|
      directory = Pathname(temporary)
      verify = -> { described_class.verify!(candidate, deployment_id: 1, status_id: 2, command:) }
      receipt = verify.call
      path = described_class.write!(directory, receipt)
      expect(JSON.parse(path.read)).to eq(receipt)
      expect(described_class.write!(directory, receipt)).to eq(path)
      expect { described_class.write!(directory, receipt.merge("candidate" => candidate.merge("candidate_number" => 42))) }
        .to raise_error("Target version already belongs to a different publication receipt")
      raw = JSON.generate(candidate.merge("artifact_sha256" => "3" * 64))
      expect { verify.call }.to raise_error("Release asset digest or candidate binding differs")
      status["state"] = "failure"
      expect { verify.call }.to raise_error("Production deployment acceptance does not match the exact candidate")
      expect(JSON.parse(path.read)).to eq(receipt)
    end
  end
end
