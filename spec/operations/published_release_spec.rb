require "spec_helper"
require "tmpdir"
require_relative "../../lib/muzeum_published_release"

RSpec.describe MuzeumPublishedRelease do
  let(:revision) { "a" * 40 }
  let(:tag) { "v0.2.1" }
  let(:release) { { "tagName" => tag, "isDraft" => false, "isPrerelease" => false, "publishedAt" => "2026-11-19T06:37:00Z" } }

  def verify(tag_target: revision)
    command = lambda do |*args|
      case args
      when [ "gh", "release", "view", tag, "--repo", "harvj/muzeum", "--json", "tagName,isDraft,isPrerelease,publishedAt" ]
        JSON.generate(release)
      when [ "gh", "api", "repos/harvj/muzeum/commits/#{tag}", "--jq", ".sha" ]
        tag_target
      else
        raise "Unexpected lookup #{args.inspect}"
      end
    end
    described_class.verify!(revision, tag:, command:)
  end

  it "accepts a stable published release only at its exact deployed SHA" do
    expect(verify).to eq(tag)
    expect { verify(tag_target: "b" * 40) }.to raise_error(/does not match/)
    expect { verify(tag_target: "invalid") }.to raise_error(/does not match/)
  end

  it "rejects drafts, prereleases, missing publication and unexpected tag names" do
    [ [ "isDraft", true ], [ "isPrerelease", true ], [ "publishedAt", nil ], [ "tagName", "v0.2.2" ] ].each do |key, value|
      original = release[key]
      release[key] = value
      expect { verify }.to raise_error(/published stable/)
      release[key] = original
    end
  end

  it "installs metadata after deployment, preserves it on a stale write, and never labels a different revision" do
    Dir.mktmpdir do |directory|
      root = Pathname(directory)
      current = root.join("current")
      current.mkdir
      shared = root.join("shared")
      shared.mkdir
      path = shared.join(described_class::FILENAME)
      marker = current.join("REVISION")
      marker.write("#{revision}\n")

      expect(described_class.from_file(path, revision:)).to be_nil
      described_class.synchronize!(root, revision, verify)
      expect(path.stat.mode & 0o777).to eq(0o640)
      expect(described_class.from_file(path, revision:)).to eq(tag)

      described_class.synchronize!(root, revision, verify)
      expect(path.stat.mode & 0o777).to eq(0o640)

      newer = "b" * 40
      marker.write("#{newer}\n")
      expect { described_class.synchronize!(root, revision, "v0.2.2") }.to raise_error(/Deployed SHA changed/)
      expect(described_class.from_file(path, revision:)).to eq(tag)
      expect(described_class.from_file(path, revision: newer)).to be_nil
    end
  end

  it "ignores malformed, oversized and legacy unbound stamps" do
    Dir.mktmpdir do |directory|
      path = Pathname(directory).join(described_class::FILENAME)
      [ tag, "#{revision} v0.2.1-preview", "#{revision} #{tag} extra", "#{revision} #{tag}#{" " * 128}" ].each do |contents|
        path.write(contents)
        expect(described_class.from_file(path, revision:)).to be_nil
      end
    end
  end
end
