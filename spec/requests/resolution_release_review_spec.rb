require "rails_helper"
require_relative "../support/oidc_flow"
require_relative "../support/leisure_configurations_fixture"

RSpec.describe "Birthday production-derived release review", type: :request do
  include OidcFlow
  include LeisureConfigurationsFixture
  before { prepare_oidc }
  after { restore_oidc }

  it "refreshes the retained catalog evidence selectively and resolves the eight-play surface separately" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "birthday-resolution")
    retained = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/release_reviews/birthday-293137.json").read)
    base_evidence = retained.fetch("evidence")
    payload = { "artist_name" => "Blur", "album_name" => "Leisure", "track_name" => "Birthday - 2012 Remaster" }
      .merge(base_evidence.fetch("source_claims", {}))
    observations = 8.times.map do |index|
      Scrobble.create!(user:, lastfm_account: user.source_account, played_at: (index + 1).days.ago, payload:)
    end
    anchor = observations.first
    surface = RecordingResolution::Ledger.attach!(anchor)
    claims = payload.slice(*RecordingResolution::PilotRunner::CLAIM_FIELDS)
    group = RecordingResolution::Group.create!(surface_id: surface.id, claims:, version: RecordingResolution::Ledger::VERSION)
    prior = RecordingResolution::Assessment.create!(group_id: group.id, version: retained.fetch("version"),
      actor: "fixture", digest: SecureRandom.hex(32), evidence: base_evidence)
    get resolution_surface_path(anchor)
    expect(response.body).to include("8 matching observations", "Earlier investigation logic", "Verified album configurations",
      "August 27, 1991", "September 24, 1991", "September 20, 1991", "Disputed source")
    expect(response.body).not_to include('aria-label="Original release"', "Unclassified additional material")
    job = CatalogImport.latest(RecordingResolution::Investigation::KIND, group.id)
    expect(job.context["reassessment_id"]).to eq(prior.id)
    get resolution_surface_path(anchor)
    expect(CatalogImport.where(kind: job.kind, entity_id: group.id).count).to eq(1)

    checked = JSON.parse(Rails.root.join("docs/design/release-configurations/tracklists.json").read)
    programs = checked.fetch("adjacent_program_editions").select { |item| %w[b11e ea3d 7916].any? { |prefix| item["id"].start_with?(prefix) } }
      .map do |item|
        source_edition(item).tap { |edition| edition["release-group"].merge!("primary-type" => "Single", "first-release-date" => edition["date"]) }
      end
    by_id = programs.index_by { |item| item.fetch("id") }
    won = "61c92a73-c3d5-43f6-8410-49156604b1cb"
    client = instance_double(Clients::Musicbrainz)
    session = instance_double(RecordingResolution::ProviderSession, provenance: [])
    allow(Clients::Musicbrainz).to receive(:new).and_return(client)
    by_id.each { |id, edition| expect(client).to receive(:edition).with(session, id, catalog: true).once.and_return(edition) }
    expect(client).to receive(:provenance_releases).with(session, won).ordered.and_raise(RecordingResolution::ProviderError, "HTTP 503")
    expect(client).to receive(:provenance_releases).with(session, won).ordered.and_return([])
    expect do
      CanonicalCatalog::Processor.new(job, session_factory: ->(*) { session }).call
      current = RecordingResolution::Assessment.where(group_id: group.id).order(id: :desc).first
      expect(current.version).to eq(RecordingResolution::Assessment::INTERPRETATION_VERSION)
      expect(current.evidence.dig("reviewed_recording_browses", won, "complete")).to eq(false)
      get resolution_surface_path(anchor)
      expect(response.body).to include("Adjacent recording programs", "She’s So High", "There’s No Other Way", "Bang", "Refresh investigation")
      post investigate_resolution_surface_path(anchor), params: { reassess: "1", assessment_id: current.id }
      refresh = CatalogImport.latest(job.kind, group.id)
      CanonicalCatalog::Processor.new(refresh, session_factory: ->(*) { session }).call
      expect(RecordingResolution::Assessment.where(group_id: group.id).order(id: :desc).first.evidence
        .dig("reviewed_recording_browses", won, "complete")).to eq(true)
    end.not_to change { [ Release.count, Recording.count, Scrobble.count, RecordingResolution::Decision.count ] }

    get resolution_surface_path(anchor)
    document = Nokogiri::HTML(response.body)
    form = document.at_css("#recording-resolution-confirmation")
    expect(form).to be_present
    expect(form.at_css('[name="construct_release"]')).to be_nil
    fields = form.css("input[name]").to_h { |node| [ node["name"], node["value"] ] }
    post decide_resolution_surface_path(anchor), params: fields
    expect(flash[:notice]).to eq("Recording decision saved.")
    expect(RecordingResolution::Ledger.effective(user).where(id: observations).map(&:effective_recording_id).uniq).to match([ kind_of(Integer) ])
    expect(Release.count).to eq(0)
    latest = RecordingResolution::Assessment.where(group_id: group.id).order(id: :desc).first
    review = RecordingResolution::ReleaseReview.new(latest.evidence)
    uk, us = review.configurations.first(2)
    post select_reviewed_configuration_resolution_surface_path(anchor),
      params: { assessment_id: latest.id, edition_mbid: uk.data["id"], admit: "1" }
    expect(response).to have_http_status(:see_other)
    album = Release.sole
    post select_reviewed_configuration_resolution_surface_path(anchor),
      params: { assessment_id: latest.id, edition_mbid: us.data["id"] }
    expect(response).to have_http_status(:see_other)
    expect(Release.sole.id).to eq(album.id)
    expect(album.reload.ingested_from_release_mbid).to eq(uk.data["id"])
    expect(ReleaseConfigurationSelection.new(user, [ album.id ]).date(album).iso).to eq("1991-09-24")
    expect(RecordingResolution::Decision.count).to eq(1)
    expect(prior.reload.evidence).to eq(base_evidence)
  end
end
