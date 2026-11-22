require "spec_helper"
require "pathname"
require_relative "../../lib/muzeum_candidate_number"

RSpec.describe MuzeumCandidateNumber do
  it "allocates per target and reuses a number only for the exact artifact" do
    Dir.mktmpdir do |temporary|
      directory = Pathname(temporary)
      source = "a" * 40
      digest = "1" * 64

      candidates = [ "0.6.1", "0.6.1", "0.6.1", "0.6.1", "0.6.2" ]
        .zip([ source, source, source, "b" * 40, source ], [ digest, digest, "2" * 64, digest, digest ])
      numbers = candidates.map do |version, revision, artifact_sha256|
        described_class.allocate(directory, version:, revision:, artifact_sha256:)
      end

      expect(numbers).to eq([ 1, 1, 2, 3, 1 ])
    end
  end

  it "serializes allocation across independent packagers" do
    Dir.mktmpdir do |temporary|
      directory = Pathname(temporary)
      allocate = ->(character) do
        described_class.allocate(directory, version: "0.6.1", revision: "a" * 40, artifact_sha256: character * 64)
      end
      inputs = %w[1 2 3 4]
      processes = inputs.map { |input| fork { exit!(allocate.call(input).positive? ? 0 : 1) } }

      expect(processes.map { |pid| Process.wait2(pid).last }).to all(be_success)
      expect(inputs.map(&allocate).sort).to eq([ 1, 2, 3, 4 ])
    end
  end
end
