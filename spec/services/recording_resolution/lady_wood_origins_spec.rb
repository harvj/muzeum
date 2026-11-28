require "rails_helper"

require_relative "../../support/lady_wood_fixture"

RSpec.describe "Lady Wood recording-first replay" do
  let(:provider) { LadyWoodFixture::Session.new }
  let(:fixture) { provider.fixture }
  let(:official) { LadyWoodFixture::OFFICIAL }
  let(:group) { LadyWoodFixture::GROUP }
  let(:client) { Clients::Musicbrainz.new }

  [
    [ 293072, "dd8c5328-1935-4ce0-a1ed-1df9e4f283cc", "d89399fb-fd54-4f36-8807-f679ac50a847" ],
    [ 293087, "d1f9b608-b554-4c99-b4e9-96ef192f6cd9", "34e97955-f1a2-45ba-98e2-051001fbbb0e" ]
  ].each do |observation_id, explicit, clean|
    it "verifies the 12-track album and the companion source IDs for observation #{observation_id}" do
      evidence = RecordingResolution::RecordingOrigins.new(client, provider).call([ explicit, clean ], retained: [])
      history = evidence.fetch("recording_publications")
      expect(history.dig(explicit, "original_groups")).to include(group)
      expect(history.dig(clean, "original_groups")).to include(group)
      expect(history.dig(explicit, "edition_coverage", group, "verified")).to include(official)
      if observation_id == 293087
        expect(history.dig(explicit, "appearances").size).to be >= 49
        expect(history.dig(explicit, "earliest_publication", "date")).to eq("2016-08-04")
        expect(history.dig(explicit, "original_groups")).to include(LadyWoodFixture::SINGLE)
        expect(provider.provenance).to include(include("endpoint" => "/ws/2/release",
          "parameters" => hash_including(recording: explicit, offset: 25)))
      end
      assessment = double(id: observation_id, evidence: evidence.merge("candidates" => [ fixture.dig("recordings", clean), fixture.dig("recordings", explicit) ]))
      plan = CanonicalCatalog::ResolutionPlan.new(assessment, clean, 1)
      expect(plan.identity.source_ids).to contain_exactly(clean, explicit)
      construction = plan.proposals.sole.construction
      expect(construction.base.slots.size).to eq(12)
      expect(construction.base.slots.pluck(:source_recording_mbid)).to include(explicit)
      expect(construction.additional_slots).to be_empty
      user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "lady-wood-#{observation_id}", lastfm_username: "lady-wood-#{observation_id}")
      canonical = plan.identity.apply!(assessment, user)
      expect(canonical.mbid).to eq(explicit)
      expect(RecordingSourceDecision.resolve(clean)).to eq(canonical)
      request = CatalogImport.create!(kind: "release_construction", state: "imported", entity_id: canonical.id, due_at: Time.current)
      release = CanonicalCatalog::ReviewedConstruction.apply!(plan.proposals.sole, request, assessment)
      slot = release.catalog_track_slots.find_by!(source_recording_mbid: explicit)
      expect(slot.recording).to eq(canonical)
      expect(slot.track_mbid).to eq(construction.base.slots.find { |track| track[:source_recording_mbid] == explicit }.fetch(:track_mbid))
      expect(Release.count).to eq(1)
    end
  end
  it "retains independently verified Lady Wood evidence when an unrelated group or browse is unavailable" do
    cool_girl = "d1f9b608-b554-4c99-b4e9-96ef192f6cd9"
    dont_talk = "dd8c5328-1935-4ce0-a1ed-1df9e4f283cc"
    provider.unavailable_single = true
    provider.unavailable_recording_browse = dont_talk
    histories = RecordingResolution::RecordingOrigins.new(client, provider).call([ cool_girl, dont_talk ], retained: [])
      .fetch("recording_publications")
    expect(histories.dig(cool_girl, "original_groups")).to eq([ group ])
    expect(histories.dig(cool_girl, "group_errors", LadyWoodFixture::SINGLE, "http_status")).to eq(503)
    expect(histories.dig(dont_talk, "original_groups")).to eq([ group ])
    expect(histories.dig(dont_talk, "appearance_browse_incomplete")).to be(true)
    expect(histories.dig(dont_talk, "earliest_publication")).to be_nil
  end
end
