require "rails_helper"
require_relative "../support/oidc_flow"
require_relative "../support/queen_short_track_fixture"

RSpec.describe "Short-track inference", type: :request do
  include OidcFlow
  include QueenShortTrackFixture

  before { prepare_oidc }
  after { restore_oidc }

  it "reviews the Queen of the Clouds interlude and keeps observed totals independent" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "queen-inference")
    release, recording, before_play, after_play = queen_short_track_fixture(user)
    get release_path(release)
    expect(response.body).to include("Timebomb", "The Love (interlude)", "Moments", "2 distinct resolved observations")
    input = Nokogiri::HTML(response.body).css("#short-track-inference input").to_h { |field| [ field["name"], field["value"] ] }
    choices = { before_id: before_play.id, after_id: after_play.id, recording_id: recording.id,
      evidence_digest: input.fetch("inference[evidence_digest]") }
    expect do
      post short_track_inference_release_path(release), params: { inference: choices.merge(decision: "confirmed") }
      expect(flash[:notice]).to eq("Inference review saved.")
      get release_path(release)
      expect(response.body).to include("Latest decision: confirmed", "2 distinct resolved observations")
      post short_track_inference_release_path(release), params: { inference: choices.merge(decision: "rejected") }
      post short_track_inference_release_path(release), params: { inference: choices.merge(decision: "rejected") }
    end.not_to change { [ Scrobble.count, RecordingResolution::Decision.count ] }
    first, second = ShortTrackInferenceDecision.order(:id)
    expect(first.decision).to eq("confirmed")
    expect(second.predecessor).to eq(first)
    expect(second.decision).to eq("rejected")
    expect(ShortTrackInferenceDecision.count).to eq(2)
    get recording_path(recording)
    expect(response.body).to include("0 resolved listening observations")
  end

  it "rejects a staged proposal once an intervening source observation exists" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "queen-stale")
    release, recording, before_play, after_play = queen_short_track_fixture(user)
    get release_path(release)
    digest = Nokogiri::HTML(response.body).at_css('input[name="inference[evidence_digest]"]')["value"]
    Scrobble.create!(user:, lastfm_account: user.source_account, played_at: before_play.played_at + 214.seconds,
      payload: { artist_name: "Tove Lo", album_name: release.title, track_name: recording.title })
    post short_track_inference_release_path(release), params: { inference: { before_id: before_play.id,
      after_id: after_play.id, recording_id: recording.id, evidence_digest: digest, decision: "confirmed" } }
    expect(flash[:alert]).to include("evidence changed")
    expect(ShortTrackInferenceDecision.count).to eq(0)
  end
end
