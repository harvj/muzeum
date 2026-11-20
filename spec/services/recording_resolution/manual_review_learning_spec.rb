require "rails_helper"

RSpec.describe RecordingResolution::ManualReviewLearning do
  def decision(id:, surface:, at:, recordings:, selected: 1, assessment_at: at, feedback: "selected")
    ranks = recordings.each_with_index.map do |mbid, index|
      { "recording_mbid" => mbid, "score" => 8 - index, "version" => RecordingResolution::Ranking::VERSION,
        "inputs" => { "version" => { "state" => index.zero? ? "contradictory" : "positive" } } }
    end
    { "id" => id, "surface" => surface, "stream" => [ surface, nil ], "at" => at,
      "snapshot" => { "version" => RecordingResolution::ReviewSnapshot::VERSION,
        "assessment" => { "created_at" => assessment_at }, "feedback" => feedback,
        "candidate_mbid" => recordings.fetch(selected), "recommended_mbid" => recordings.first, "ranking" => ranks } }
  end

  it "learns in shadow with a chronological, identity-disjoint holdout and excludes future evidence" do
    examples = [
      decision(id: 1, surface: 1, at: "2026-11-01T12:00:00Z", recordings: %w[a b]),
      decision(id: 2, surface: 2, at: "2026-11-02T12:00:00Z", recordings: %w[c d]),
      decision(id: 3, surface: 3, at: "2026-11-03T12:00:00Z", recordings: %w[e f], assessment_at: "2026-11-05T12:00:00Z"),
      decision(id: 4, surface: 4, at: "2026-11-03T12:00:00Z", recordings: %w[g h], feedback: "rejected"),
      decision(id: 5, surface: 5, at: "2026-11-05T12:00:00Z", recordings: %w[c j]),
      decision(id: 6, surface: 1, at: "2026-11-06T12:00:00Z", recordings: %w[k l]),
      decision(id: 7, surface: 7, at: "2026-11-03T12:00:00Z", recordings: %w[m n], selected: 0),
      decision(id: 8, surface: 7, at: "2026-11-03T13:00:00Z", recordings: %w[m n]),
      decision(id: 9, surface: 7, at: "2026-11-03T14:00:00Z", recordings: %w[m n], feedback: "deferred")
    ]
    result = described_class.call(examples.reverse, split_at: "2026-11-04T00:00:00Z")
    expect(result).to include("training_examples" => 1, "excluded_overlap" => 2,
      "held_out_examples" => 2, "baseline_top_choice" => 0, "shadow_top_choice" => 2)
    expect(result.fetch("held_out_recommendation_outcomes")).to eq("overridden" => 2)
    expect(result.fetch("review_events")).to include("rejected" => 1, "deferred" => 1)
    expect(result.fetch("factor_adjustments").values.sort).to eq([ -1, 1 ])
  end
end
