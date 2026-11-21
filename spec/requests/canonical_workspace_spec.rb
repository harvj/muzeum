require "rails_helper"
require_relative "../support/oidc_flow"
require_relative "../support/catalog_fixtures"
require_relative "../support/discovery_replay"

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

  it "renders the Regent's Court source, three checked tracklists and explicit decision scopes" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "regents-court-review")
    fixture_dir = Rails.root.join("spec/fixtures/recording_resolution/discovery")
    fixture = JSON.parse(fixture_dir.join("corpus.json").read)
    daytrotter = JSON.parse(fixture_dir.join("daytrotter.json").read)
    fixture.fetch("releases")[daytrotter.fetch("id")] = daytrotter
    example = fixture.fetch("cases").find { |row| row["id"] == "regents-court-292999" }
    source = example.fetch("surface")
    claims = example.fetch("claims")
    payload = claims.merge("artist_name" => source.fetch("artist"), "album_name" => source.fetch("album"), "track_name" => source.fetch("track"))
    plays = 5.times.map do |offset|
      Scrobble.create!(user:, lastfm_account: user.source_account, played_at: offset.days.ago,
        source_fingerprint: SecureRandom.hex(32), payload:)
    end
    observation = plays.first
    surface = RecordingResolution::Ledger.attach!(observation)
    group = RecordingResolution::Group.create!(surface_id: surface.id, version: RecordingResolution::Ledger::VERSION, claims:)
    session = DiscoveryReplay::Session.new(fixture, example)
    evidence = RecordingResolution::Evaluator.new(session, discogs: nil, workspace: true, review_alternative: true).call(surface, claims)
    # Reproduce the historical scoring that production stored before the caption rule changed.
    evidence["ranking"] = RecordingResolution::Ranking.call(surface, evidence, caption_bonus: true)
    assessment = RecordingResolution::Assessment.create!(group_id: group.id, version: "fixture", actor: "fixture",
      digest: SecureRandom.hex(32), evidence:)

    get resolution_surface_path(observation, play: observation.id, assessment: assessment.id)
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css(".review-heading h1").text).to eq(source.fetch("track"))
    expect(doc.css(".review-source-claims dt").map(&:text)).to eq(%w[Artist Album])
    expect(doc.css(".review-source-claims dd").map(&:text)).to eq(source.values_at("artist", "album"))
    expect(doc.css(".review-edition").map(&:text).join(" ")).to include("deluxe edition", "2011", "Daytrotter Session")
    expect(doc.css(".review-candidate").map { |card| card.css(".review-tracks li").size }).to eq([ 18, 14, 4 ])
    expect(doc.css(".review-track-match").size).to eq(3)
    expect(doc.css(".review-score strong").map(&:text)).to eq(%w[9 8 7])
    expect(doc.text).to include("historical scoring", "3 plausible recordings found", "Assign only observation #{observation.id}", "2:03")

    get resolution_surface_path(observation, assessment: assessment.id)
    expect(response.body).to include("Assign 5 matching observations", "future exact matches")
    expect(RecordingResolution::Decision.count).to eq(0)
  end

  it "protects the library, workspace and import actions" do
    [ artists_path, releases_path, recordings_path, resolution_surfaces_path ].each do |path|
      get path
      expect(response).to redirect_to(root_path)
    end
    get artists_path(profile: "qalephd", action_name: "index")
    expect(response).to redirect_to(root_path)
    post import_artist_path(1)
    expect(response).to redirect_to(root_path)
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
    expect(response.body).to include("Assign 2 matching observations", "A checked MusicBrainz edition contains this track slot")
    expect(response.body).not_to include("Release edition to verify")
    get resolution_surface_path(example, before: second.id)
    expect(response.body).to include("2 matching observations")
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

    post decide_resolution_surface_path(example), params: { scope: "scrobble", play_id: second.id, mode: "unresolved" }
    head = RecordingResolution::Decision.last
    expect(head).to have_attributes(scrobble_id: second.id, reason: "Left unresolved",
      evidence: a_hash_including("reason_code" => "left_unresolved"))
    get resolution_surfaces_path(filter: "exceptions")
    expect(response.body).to include("Signals")
    expect(RecordingResolution::Ledger.effective(user).find(second.id).effective_recording_id).to be_nil
    get resolution_surface_path(example, play: second.id)
    expect(response.body).to include("Assign only observation", "Return to inheritance")
    post decide_resolution_surface_path(example), params: { scope: "scrobble", play_id: second.id, mode: "inherit", head: head.id }
    expect(RecordingResolution::Decision.last.evidence.fetch("reason_code")).to eq("restore_inheritance")
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

  it "queues a missing investigation on open, shares the request for exact matches, and shows a worker outcome" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "catalog-request")
    observation = catalog_observation(user)
    second = catalog_observation(user, time: 1.day.ago)

    expect { get resolution_surface_path(observation) }.to change(CatalogImport, :count).by(1)
    expect(response.body).to include("Unresolved", "Investigation pending")
    expect { get resolution_surface_path(second) }.not_to change(CatalogImport, :count)
    request = CatalogImport.where(kind: RecordingResolution::Investigation::KIND).sole
    CanonicalCatalog::Processor.new(request, session_factory: ->(*) { CatalogFixtures::Session.new }).call
    expect(request.reload.state).to eq("imported")
    get resolution_surface_path(second)
    expect(response.body).to include("Muzeum’s recommendation", "Verified source recording identifier", "2 current matching observations")

    assessment = RecordingResolution::Ledger.assessments(user).sole
    post decide_resolution_surface_path(second), params: { mode: "resolved", scope: "surface",
      recording_mbid: CatalogFixtures::IDS[:studio], assessment_id: assessment.id,
      comment: "Checked the studio version" }
    decision = RecordingResolution::Decision.sole
    expect(decision).to have_attributes(reason: "Confirmed candidate", assessment_id: assessment.id, actor: "listener", user_id: user.id)
    expect(decision.evidence).to include("reason_code" => "confirmed_candidate", "comment" => "Checked the studio version",
      "scoring_version" => RecordingResolution::Ranking::VERSION, "affected_scope" => "surface")
    get resolution_surface_path(second)
    expect(response.body).to include("Inherited from your exact-surface assignment", "Checked the studio version")
    expect(decision.evidence.fetch("candidate_scores").first.fetch("recording_mbid")).to eq(CatalogFixtures::IDS[:studio])
    snapshot = decision.evidence.fetch("review_snapshot")
    expect(snapshot).to include("feedback" => "selected", "candidate_mbid" => CatalogFixtures::IDS[:studio],
      "affected_observation_count" => 2, "ranking" => assessment.evidence.fetch("ranking"))
    expect(snapshot.fetch("assessment")).to include("id" => assessment.id, "digest" => assessment.digest)
    expect(snapshot.fetch("ranking").first.dig("inputs", "recording_identifier", "state")).to eq("positive")

    post defer_resolution_surface_path(second), params: { feedback: "rejected", assessment_id: assessment.id,
      recording_mbid: CatalogFixtures::IDS[:studio], head: decision.id }
    rejection = RecordingResolution::Decision.last
    expect(rejection).to have_attributes(predecessor_id: decision.id, recording_id: decision.recording_id, mode: "resolved")
    expect(rejection.evidence.fetch("review_snapshot")).to include("feedback" => "rejected",
      "candidate_mbid" => CatalogFixtures::IDS[:studio], "affected_observation_count" => 0)
    expect(RecordingResolution::Ledger.effective(user).find(second.id).effective_recording_id).to eq(decision.recording_id)
    expect(Scrobble.find(observation.id).payload).to eq(observation.payload)
  end

  it "distinguishes an empty investigation from a provider failure and records a no-change deferral" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "catalog-request")
    observation = Scrobble.create!(user:, lastfm_account: user.source_account, played_at: Time.current,
      payload: { "artist_name" => "No Catalog Match", "track_name" => "Unidentified Recording" })
    get resolution_surface_path(observation)
    request = CatalogImport.where(kind: RecordingResolution::Investigation::KIND).sole
    CanonicalCatalog::Processor.new(request, session_factory: ->(*) { CatalogFixtures::Session.new }).call
    get resolution_surface_path(observation)
    expect(response.body).to include("No credible candidates", "Investigation completed")
    expect(response.body).not_to include("Provider evidence unavailable")
    post investigate_resolution_surface_path(observation)
    refreshed = CatalogImport.latest(RecordingResolution::Investigation::KIND, request.entity_id)
    session = instance_double(RecordingResolution::ProviderSession, current_request: { "provider" => "musicbrainz", "endpoint" => "/ws/2/recording" }, provenance: [])
    allow(session).to receive(:get).and_raise(RecordingResolution::ProviderError.new("Fixture outage", terminal: true))
    CanonicalCatalog::Processor.new(refreshed, session_factory: ->(*) { session }).call
    get resolution_surface_path(observation)
    expect(response.body).to include("Provider evidence unavailable")

    post defer_resolution_surface_path(observation), params: { comment: "Investigate later" }
    expect(response).to redirect_to(resolution_surface_path(observation))
    expect(RecordingResolution::Decision.sole).to have_attributes(mode: "inherit",
      evidence: a_hash_including("reason_code" => "deferred_review", "comment" => "Investigate later"))
    expect(RecordingResolution::Ledger.effective(user).find(observation.id).effective_recording_id).to be_nil
  end

  it "distinguishes a legacy partial recording from a canonical provider identity in Resolution and Archive" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)
    LastfmAccount.associate!(user, "catalog-request")
    observation = catalog_observation(user)
    recording = Recording.create!(title: "Legacy recording", mbid: "legacy-reference")
    RecordingResolution::Ledger.record!(listener: user, scrobble: observation, scope: :surface, mode: "resolved",
      reason: "Historical free text", recording:)
    get resolution_surface_path(observation)
    expect(response.body).to include("Partially resolved", "Historical free text")
    expect(CatalogImport.count).to eq(0)
    get archive_path
    expect(response.body).to include("Partially resolved", "Reported by Last.fm")
  end
end
