require "rails_helper"

RSpec.describe RecordingResolution::Evaluator do
  it "recovers a credited title variant while preserving abstention and version evidence" do
    surface = RecordingResolution::RealCorpusEvaluation::Observation.new(
      artist: "Dead Can Dance", track: "ACT I: Sea Borne (live)", album: nil)
    digital = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/releases/dionysus_digital.json").read)
    solo = digital.dig("media", 0, "tracks", 0, "recording")
    session = double(current_request: { "parameters" => { "query" => "captured request" } })
    paths = []
    allow(session).to receive(:get) do |_provider, path, params:, &project|
      paths << params.fetch(:query)
      recordings = params.fetch(:query).include?('recording:"Sea Borne') ? [ solo ] : []
      { "data" => project.call("recordings" => recordings, "count" => recordings.size, "offset" => 0) }
    end

    baseline = described_class.new(session, discogs: nil, workspace: true).call(surface, {})
    expect(baseline.fetch("candidates")).to be_empty
    evidence = described_class.new(session, discogs: nil, workspace: true, adaptive: true).call(surface, {})
    expect(evidence.fetch("source_claims")).to eq({})
    expect(surface.track).to eq("ACT I: Sea Borne (live)")
    expect(evidence.fetch("adaptive_searches").length).to be <= 3
    expect(paths.uniq).to eq(paths.drop(1))
  end

  it "retains the real recording from a stripped qualifier as a review choice only" do
    surface = RecordingResolution::RealCorpusEvaluation::Observation.new(
      artist: "Dead Can Dance", track: "Sea Borne (live)", album: nil)
    digital = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/releases/dionysus_digital.json").read)
    solo = digital.dig("media", 0, "tracks", 0, "recording")
    session = double(current_request: { "parameters" => { "query" => "captured request" } })
    allow(session).to receive(:get) do |_provider, _path, params:, &project|
      rows = params.fetch(:query).include?('recording:"Sea Borne"') ? [ solo ] : []
      { "data" => project.call("recordings" => rows, "count" => rows.size, "offset" => 0) }
    end
    evidence = described_class.new(session, discogs: nil, workspace: true, adaptive: true).call(surface, {})
    expect(evidence.fetch("adaptive_searches").length).to eq(2)
    rank = RecordingResolution::Ranking.call(surface, evidence, source_hints: true).sole
    expect(rank.fetch("recording_mbid")).to eq(solo.fetch("id"))
    expect(rank.dig("inputs", "title", "state")).to eq("contradictory")
    expect(RecordingResolution::Ranking.recommended?([ rank ])).to be(false)
  end
end
