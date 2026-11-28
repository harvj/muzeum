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
      document = Nokogiri::HTML(response.body)
      expect(document.css('input[type="radio"][name="construct_release"]')).to be_empty
      source_ids = document.css('.release-configuration-sources a').map { |link| link["href"].split("/").last }
      expect(source_ids).to include(edition.fetch("id"))
      expect(source_ids.size).to eq(example[:file] == "crash" ? 16 : 2)
      expect(source_ids).not_to include("3e70fdcd-c807-48f5-be82-ffe256f0884d")
      selected_source = document.at_css('#recording-resolution-confirmation input[name="construct_release"]')["value"]
      post decide_resolution_surface_path(target), params: confirmation.merge(assessment_id: assessment.id, construct_release: selected_source)
      expect(flash[:notice]).to eq("Recording decision saved.")
      release = Release.sole
      evidence = RecordingResolution::ReleaseTracklist.new(release).revision.evidence
      expect(evidence.fetch("checked_recording_appearances").select { |source| source["supports_base_configuration"] }.pluck("id"))
        .to match_array(source_ids)
      alternatives = evidence.fetch("checked_recording_appearances").reject { |source| source["supports_base_configuration"] }
      expect(alternatives.pluck("track_count").uniq).to include(example[:file] == "crash" ? 16 : 15)
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
