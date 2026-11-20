require "rails_helper"

RSpec.describe RecordingResolution::Ranking do
  let(:cases) { JSON.parse(Rails.root.join("spec/fixtures/recording_resolution/shadow_cases.json").read) }

  it "ranks reviewed cases deterministically and exposes simulated false positives without assigning recordings" do
    results = nil
    expect { results = RecordingResolution::ShadowEvaluation.call(cases) }.not_to change(RecordingResolution::Decision, :count)
    expect(results.fetch("outcomes")).to eq("correct" => 1, "ambiguous" => 1, "review_required" => 1,
      "false_positive" => 1, "unsupported" => 1)
    expect(RecordingResolution::ShadowEvaluation.call(cases.reverse).fetch("cases").reverse).to eq(results.fetch("cases"))
    results.fetch("cases").flat_map { |result| result.fetch("ranking") }.each do |rank|
      expect(rank.fetch("score")).to eq(rank.fetch("inputs").values.sum { |input| input.fetch("weight") })
      expect(rank.dig("inputs", "duration")).to eq("state" => "unavailable", "weight" => 0)
    end
    first = results.fetch("cases").first.fetch("ranking")
    expect(first.second.dig("inputs", "version", "state")).to eq("contradictory")
  end
end
