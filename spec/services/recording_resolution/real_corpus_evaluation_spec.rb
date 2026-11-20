require "rails_helper"

RSpec.describe RecordingResolution::RealCorpusEvaluation do
  let(:fixtures) { Rails.root.join("spec/fixtures/recording_resolution/real_corpus") }
  let(:catalog) { JSON.parse(fixtures.join("catalog.json").read) }
  let(:cases) { JSON.parse(fixtures.join("cases.json").read) }
  subject(:evaluation) { described_class.new(catalog:, cases:) }

  it "replays the exact decision-time evidence and ordered baseline without later labels" do
    expect(evaluation.snapshots).to eq(JSON.parse(fixtures.join("snapshots.json").read))
    relabeled = cases.map { |example| example.except("reviewed_ref", "initial_choice_ref") }
    expect(described_class.new(catalog:, cases: relabeled).snapshots).to eq(evaluation.snapshots)
  end

  it "reports recommendation safety separately from unique top placement" do
    report = evaluation.evaluate

    expect(report.fetch("learning")).to include("training_examples" => 3, "excluded_overlap" => 0)
    expect(report.fetch("baseline")).to eq("correct" => 1, "false_positive" => 1, "ambiguous_abstention" => 3, "abstained" => 4)
    expect(report.fetch("shadow")).to eq(report.fetch("baseline"))
    expect(report.fetch("baseline_top")).to include("correct" => 3, "false_positive" => 2)
    expect(report.fetch("shadow_top")).to include("correct" => 5, "false_positive" => 1)
    expect(report.fetch("simulated_corrections")).to eq(3)
    expect(report.fetch("rank_order_controls")).to include("human_responses" => 0, "always_first_choices_changed" => 4, "identity_fixed_choices_changed" => 0)
  end

  it "rejects group overlap even when candidates differ" do
    held_out = cases.find { |example| example["partition"] == "held_out" }
    held_out["observation_group"] = cases.first.fetch("observation_group")

    expect { evaluation }.to raise_error(ArgumentError, /observation groups overlap/)
  end

  it "rejects recording overlap even when a shared recording is only an alternative" do
    held_out = cases.find { |example| example["partition"] == "held_out" }
    held_out.fetch("candidate_refs") << cases.first.fetch("candidate_refs").first

    expect { evaluation }.to raise_error(ArgumentError, /recording IDs overlap/)
  end

  it "balances positions while keeping evidence fixed and reference labels and scores hidden" do
    packets = evaluation.order_packets
    expect(packets.size).to eq(3)

    packets.each do |packet|
      expect(packet.keys).to contain_exactly("packet", "surface", "variants")
      variants = packet.fetch("variants")
      candidates = variants.first
      candidates.each do |candidate|
        expect(candidate.keys).to contain_exactly("recording_mbid", "catalog", "evidence")
        expect(candidate.fetch("evidence").values.flat_map(&:keys)).not_to include("weight")
      end
      expect(variants).to all(match_array(candidates))
      variants.transpose.each { |position| expect(position).to match_array(candidates) }
    end
  end
end
