require "rails_helper"
require_relative "../support/oidc_flow"
require_relative "../support/catalog_fixtures"

RSpec.describe "Canonical library and resolution workspace", type: :request do
  include OidcFlow
  include CatalogFixtures
  before { prepare_oidc }
  after { restore_oidc }

  it "withholds indistinguishable edition choices" do
    candidate = { "id" => CatalogFixtures::IDS[:studio], "releases" => [
      { "title" => "ESTRUS", "id" => CatalogFixtures::IDS[:edition] },
      { "title" => "ESTRUS", "id" => CatalogFixtures::IDS[:other] },
      { "title" => "ESTRUS", "id" => CatalogFixtures::IDS[:track], "date" => "2026", "country" => "US" }
    ] }
    assessment = RecordingResolution::Assessment.new(evidence: {})
    expect(RecordingResolution::Workspace.editions(candidate, assessment)).to eq(
      [ [ "ESTRUS · 2026 · US", CatalogFixtures::IDS[:track] ] ])
  end

  it "protects the library, workspace and import actions" do
    [ artists_path, releases_path, recordings_path, resolution_surfaces_path ].each do |path|
      get path
      expect(response).to redirect_to(new_session_path)
    end
    post import_artist_path(1)
    expect(response).to redirect_to(new_session_path)
  end

  it "reviews an exact surface, records explicit choices, rejects stale writes, and respects archive revocation" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "catalog-request")
    example = catalog_observation(user)
    second = catalog_observation(user, time: 1.day.ago)
    assessment = catalog_assessment(example)
    mbid = CatalogFixtures::IDS[:studio]
    choice = { mode: "resolved", scope: "surface", recording_mbid: mbid, assessment_id: assessment.id, reason: "Confirmed studio version" }

    get resolution_surfaces_path(filter: "suggested")
    expect(response.body).to include("Signals", "Night Lines", "Night Drive")
    get resolution_surface_path(example)
    expect(response.body).to include("Apply to all", "Observed edition slot")
    expect(response.body).not_to include("Release edition to verify")
    get resolution_surface_path(example, before: second.id)
    expect(response.body).to include("2 observations with these exact Last.fm strings")
    expect { post decide_resolution_surface_path(example), params: choice }.to change(RecordingResolution::Decision, :count).by(1)
    expect(response).to redirect_to(resolution_surface_path(example))
    get resolution_surfaces_path(filter: "resolved")
    expect(response.body).to include("Signals")
    get resolution_surfaces_path(filter: "unresolved")
    expect(response.body).not_to include("Signals")
    import = CatalogImport.where(kind: "recording").sole
    expect(import.context).not_to have_key("edition_mbid")
    get resolution_surface_path(example)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("select[name='edition_mbid']").ancestors("form").first["action"]).to eq(admit_resolution_surface_path(example))
    expect(response.body).to include("checked disc 1, track 1")
    import.update!(state: "imported")
    expect do
      post admit_resolution_surface_path(example), params: choice.merge(edition_mbid: CatalogFixtures::IDS[:edition])
    end.not_to change(RecordingResolution::Decision, :count)
    expect(flash[:notice]).to include("Release verification requested")
    expect(CatalogImport.active.sole.context["edition_mbid"]).to eq(CatalogFixtures::IDS[:edition])
    expect { post decide_resolution_surface_path(example), params: choice }.not_to change(RecordingResolution::Decision, :count)
    expect(flash[:alert]).to include("changed")

    post decide_resolution_surface_path(example), params: { scope: "scrobble", play_id: second.id, mode: "unresolved", reason: "Unclear version" }
    head = RecordingResolution::Decision.last
    expect(head.scrobble_id).to eq(second.id)
    get resolution_surfaces_path(filter: "exceptions")
    expect(response.body).to include("Signals")
    expect(RecordingResolution::Ledger.effective(user).find(second.id).effective_recording_id).to be_nil
    get resolution_surface_path(example, play: second.id)
    expect(response.body).to include("Only this time", "Return to inheritance")
    post decide_resolution_surface_path(example), params: { scope: "scrobble", play_id: second.id, mode: "inherit", reason: "Same version", head: head.id }
    later = catalog_observation(user, time: 1.day.from_now)
    expect(RecordingResolution::Ledger.effective(user).find(later.id).effective_recording_id).to eq(Recording.find_by!(mbid:).id)
    expect(RecordingResolution::Ledger.effective(user).find(second.id).effective_recording_id).to eq(Recording.find_by!(mbid:).id)

    other = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "other-resolution-listener")
    LastfmAccount.associate!(other, user.source_account.username)
    RecordingResolution::Ledger.record!(listener: other, scrobble: example, scope: :surface, mode: "unresolved", reason: "Other listener private reason")
    get resolution_surface_path(example)
    expect(response.body).not_to include("Other listener private reason")
    get recording_path(Recording.find_by!(mbid:))
    expect(response.body).to include("3 resolved listening observations")
    user.user_lastfm_accounts.active.sole.revoke!
    get resolution_surface_path(example)
    expect(response).to have_http_status(:not_found)
    post decide_resolution_surface_path(example), params: choice
    expect(response).to have_http_status(:not_found)
  end
end
