require "spec_helper"
require "tmpdir"
require "pathname"
require_relative "../../lib/muzeum_published_release"

RSpec.describe MuzeumPublishedRelease do
  let(:revision) { "a" * 40 }
  let(:target) { "b" * 40 }
  let(:release) { { "tagName" => "v0.2.0", "isDraft" => false, "isPrerelease" => false, "publishedAt" => "2026-11-17T18:33:58Z" } }

  def verify(merge_base: target, tag_target: target)
    command = lambda do |*args|
      case args
      when [ "gh", "release", "view", "--repo", "harvj/muzeum", "--json", "tagName,isDraft,isPrerelease,publishedAt" ]
        JSON.generate(release)
      when [ "gh", "api", "repos/harvj/muzeum/commits/#{release.fetch('tagName')}", "--jq", ".sha" ]
        tag_target
      when [ "git", "merge-base", tag_target, revision ]
        merge_base
      else
        raise "Unexpected lookup #{args.inspect}"
      end
    end
    described_class.verify!(revision, command:)
  end

  it "accepts a published stable tag only when its resolved commit is in the candidate history" do
    expect(verify).to eq("v0.2.0")
    expect(verify(merge_base: revision, tag_target: revision)).to eq("v0.2.0")
    expect { verify(merge_base: "c" * 40) }.to raise_error(/candidate history/)
    expect { verify(tag_target: "invalid") }.to raise_error(/candidate history/)
  end

  it "rejects drafts, prereleases, missing publication and invalid tag names" do
    [ [ "isDraft", true ], [ "isPrerelease", true ], [ "publishedAt", nil ], [ "tagName", "v0.2.0-preview" ] ].each do |key, value|
      original = release[key]
      release[key] = value
      expect { verify }.to raise_error(/published stable/)
      release[key] = original
    end
  end

  it "reads a valid local stamp and omits absent or invalid values" do
    Dir.mktmpdir do |directory|
      path = Pathname(directory).join(described_class::FILENAME)
      expect(described_class.from_file(path)).to be_nil
      path.write("v0.2.0\n")
      expect(described_class.from_file(path)).to eq("v0.2.0")
      path.write("v0.2.0-preview\n")
      expect(described_class.from_file(path)).to be_nil
    end
  end
end
