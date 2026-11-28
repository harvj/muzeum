require "rails_helper"
require_relative "../support/oidc_flow"
require_relative "../support/discovery_replay"
require_relative "../support/release_membership_fixture"

RSpec.describe "Release-backed recording resolution", type: :request do
  include OidcFlow
  include ReleaseMembershipFixture
  before { prepare_oidc }
  after { restore_oidc }

  ReleaseMembershipFixture::CASES.each do |example|
    it "refreshes and resolves #{example[:track]} only with checked release membership" do
      finish_oidc
      user = User.find_by!(oidc_subject: @subject)
      LastfmAccount.associate!(user, "release-backed")
      plays, previous, edition, studio, provider = seed_release_membership_case(user, example)
      target = plays.first
      original_play_data = plays.map { |play| play.reload.attributes }
      historical = previous.evidence
      mbid = studio.fetch("id")
      group_mbid = edition.dig("release-group", "id")

      confirmation = { scope: "surface", mode: "resolved", recording_mbid: mbid }
      expect do
        post decide_resolution_surface_path(target), params: confirmation.merge(assessment_id: previous.id)
      end.not_to change { [ Recording.count, Release.count, RecordingResolution::Decision.count ] }
      expect(flash[:alert]).to include("Verify and admit a release")

      get resolution_surface_path(target)
      request = CatalogImport.where(kind: RecordingResolution::Investigation::KIND).sole
      CanonicalCatalog::Processor.new(request, session_factory: ->(*) { provider }).call
      expect(request.reload.state).to eq("imported")
      assessment = RecordingResolution::Assessment.where(group_id: previous.group_id).order(:id).last!
      expect(assessment.evidence.dig("recording_publications", mbid, "original_groups")).to include(group_mbid)
      expect(assessment.evidence.fetch("candidates").pluck("id")).to include(example[:competing])
      expect(provider.paths).to include("/ws/2/recording/#{mbid}")

      get resolution_surface_path(target, candidate: mbid)
      expect(response.body).to include("Admit 1 new release", "Resolve all #{example[:observations]}")
      post decide_resolution_surface_path(target), params: confirmation.merge(assessment_id: assessment.id, construct_release: edition["id"])
      expect(flash[:notice]).to eq("Recording decision saved.")
      release = Release.sole
      recording = Recording.find_by!(mbid:)
      expect(recording.verified_release_membership?).to be(true)
      expect(release.catalog_track_slots.base_sequence.count).to eq(example[:tracks])
      expect(release.catalog_track_slots.base_sequence.find_by!(position: example[:position]).recording).to eq(recording)
      expect(RecordingResolution::Ledger.effective(user).where(id: plays.map(&:id)).map(&:effective_recording_id)).to eq([ recording.id ] * plays.size)
      expect(plays.map { |play| play.reload.attributes.except("recording_surface_id") }).to eq(original_play_data.map { |data| data.except("recording_surface_id") })
      expect(previous.reload.evidence).to eq(historical)
    end
  end
end
