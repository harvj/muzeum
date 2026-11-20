require "rails_helper"
require_relative "../../support/catalog_fixtures"

RSpec.describe RecordingResolution::ManualReviewBaseline do
  include CatalogFixtures

  it "counts scoped review events and recorded rank agreement without treating deferrals as confirmations" do
    listener = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "learning-fixture", lastfm_username: "learning-fixture")
    other = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "other-learning-fixture")
    LastfmAccount.associate!(other, listener.source_account.username)
    play = catalog_observation(listener)
    studio = Recording.create!(title: "Signals", mbid: CatalogFixtures::IDS.fetch(:studio))
    alternate = Recording.create!(title: "Signals alternate", mbid: CatalogFixtures::IDS.fetch(:other))
    evidence = { "scoring_version" => RecordingResolution::Ranking::VERSION,
      "candidate_scores" => [ { "recording_mbid" => studio.mbid, "score" => 9 }, { "recording_mbid" => alternate.mbid, "score" => 4 } ],
      "comment" => "Fixture private note" }

    head = RecordingResolution::Ledger.record!(listener:, scrobble: play, scope: :surface, mode: "resolved",
      reason: "Confirmed candidate", recording: studio, metadata: evidence)
    correction = RecordingResolution::Ledger.record!(listener:, scrobble: play, scope: :surface, mode: "resolved",
      reason: "Historical text", recording: alternate, metadata: evidence, expected_head: head.id)
    RecordingResolution::Ledger.record!(listener:, scrobble: play, scope: :surface, mode: "resolved",
      reason: "Deferred review", recording: alternate, metadata: { "reason_code" => "deferred_review" }, expected_head: correction.id)
    RecordingResolution::Ledger.record!(listener: other, scrobble: play, scope: :surface, mode: "unresolved", reason: "Other review")

    result = nil
    expect { result = described_class.call(listener) }.not_to change(RecordingResolution::Decision, :count)
    expect(result).to include("decision_events" => 3, "superseded_events" => 2,
      "actions" => { "resolved" => 2, "deferred" => 1 },
      "recorded_ranking_comparisons" => { "selected_unique_top" => 1, "selected_lower_rank" => 1 })
    expect(result.to_json).not_to include("Fixture private note", studio.mbid, alternate.title, "Historical text")
    expect(described_class.call(listener, before_id: correction.id).fetch("decision_events")).to eq(1)
    expect(described_class.call(other).fetch("actions")).to eq("unresolved" => 1)
  end
end
