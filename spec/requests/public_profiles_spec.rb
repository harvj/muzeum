require "rails_helper"
require_relative "../support/oidc_flow"
require_relative "../support/public_profile_fixture"

RSpec.describe "Public listening profiles", type: :request do
  include OidcFlow
  include PublicProfileFixture

  let(:fixture) { listening_profile_fixture }
  let(:profile) { fixture.fetch(:profile) }

  before { prepare_oidc }
  after { restore_oidc }

  it "offers a public homepage, disabled onboarding, and no discovery or direct access to private profiles" do
    profile
    expect { get root_path, headers: { "Sec-Fetch-Mode" => "navigate", "Sec-Fetch-Dest" => "document" } }
      .not_to change(OidcAttempt, :count)
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("input#future-lastfm-username[disabled]")).to be_present
    expect(html.at_css("button[disabled]").text).to eq("Get Started")
    expect(html.at_css("form")).to be_nil
    expect(response.body).not_to include("qalephd", "An unrecognized track")

    profile.record_consent!(consenting_owner: fixture.fetch(:owner), reference: "disposable-consent-fixture")
    get root_path
    expect(response.body).not_to include(public_profile_path(profile))
    get public_profile_path(profile)
    expect(response).to have_http_status(:not_found)
    get public_profile_recording_path(profile, fixture.fetch(:recording))
    expect(response).to have_http_status(:not_found)
  end

  it "shows the signed-in navigation on the public homepage until the session expires" do
    finish_oidc
    user = User.find_by!(oidc_subject: @subject)

    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to include("no-store")
    html = Nokogiri::HTML(response.body)
    expect(html.at_css('nav[aria-label="Music library"]')).to be_present
    expect(html.at_css('.harvj-session > summary')).to be_present
    expect(html.css("header a").map(&:text)).not_to include("Log In")

    user.sessions.sole.update!(last_seen_at: 13.hours.ago)
    expect { get root_path }.not_to change(OidcAttempt, :count)
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css('.harvj-session > summary')).to be_nil
    expect(html.css("header a").map(&:text)).to include("Log In")
  end

  it "shows only the published archive and its canonical context to anonymous visitors" do
    authorize_fixture_publication(fixture)
    other = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "private-reader", lastfm_username: "private-name")
    private_play = other.scrobbles.create!(played_at: Time.current,
      payload: { artist_name: "Private artist", track_name: "Private song" })
    private_recording = Recording.create!(title: "Private catalog recording", mbid: SecureRandom.uuid)
    RecordingResolution::Ledger.record!(listener: other, scrobble: private_play, scope: :scrobble,
      mode: "resolved", reason: "Private", recording: private_recording)

    get root_path
    expect(response.body).to include(public_profile_path(profile))
    get public_profile_path(profile)
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.body).to include('name="turbo-cache-control" content="no-cache"')
    expect(response.body).to include("Harbor Lights", "An unrecognized track", "Unresolved")
    expect(response.body).not_to include("Private song", "private-name", "resolution/", "unpublished source detail", "Private fixture rationale",
      "disposable-consent-fixture", "disposable-policy-fixture")
    expect(response.body.index("Harbor Lights")).to be < response.body.index("An unrecognized track")

    get public_profile_artists_path(profile)
    expect(response.body).to include(public_profile_artist_path(profile, fixture.fetch(:artist)))
    get public_profile_artist_path(profile, fixture.fetch(:artist))
    navigation = Nokogiri::HTML(response.body).at_css(".library-nav")
    expect(navigation.css('span[aria-current="page"]').map(&:text)).to eq([ "Artists" ])
    expect(navigation.at_css("a[href='#{public_profile_path(profile)}']").text).to eq("Archive")
    expect(response.body).to include(public_profile_release_path(profile, fixture.fetch(:album)))
    get public_profile_releases_path(profile)
    expect(response.body).to include("Harbor Sessions")
    get public_profile_release_path(profile, fixture.fetch(:album))
    expect(response.body).to include("The Empty Pier", "Resolved plays")
    expect(response.body).not_to include("Catalog import", "Catalog import status")
    get public_profile_recording_path(profile, fixture.fetch(:recording))
    expect(response.body).to include("1 resolved listening observation")
    get public_profile_recording_path(profile, fixture.fetch(:unplayed))
    expect(response.body).to include("0 resolved listening observations")
    get public_profile_recordings_path(profile)
    expect(response.body).not_to include("Private catalog recording")
    get public_profile_recording_path(profile, private_recording)
    expect(response).to have_http_status(:not_found)

    grant = fixture.fetch(:owner).user_lastfm_accounts.active.find_by!(lastfm_account: fixture.fetch(:account))
    grant.revoke!
    get public_profile_path(profile)
    expect(response).to have_http_status(:not_found)
    grant.update!(revoked_at: nil)
    get public_profile_path(profile)
    expect(response).to have_http_status(:not_found)
  end

  it "does not transfer publication approval to a reconciled source username" do
    authorize_fixture_publication(fixture)
    fixture.fetch(:account).reconcile_name!("different-name", reason: "Disposable fixture rename")
    get public_profile_path("qalephd")
    expect(response).to have_http_status(:not_found)
    get public_profile_path("different-name")
    expect(response).to have_http_status(:not_found)
  end

  it "uses chronological keyset paging without losing same-second plays" do
    authorize_fixture_publication(fixture)
    50.times do |index|
      fixture.fetch(:owner).scrobbles.create!(played_at: Time.utc(2024, 5, 4),
        payload: { artist_name: "Paging", track_name: "Paging fixture #{index}" })
    end
    get public_profile_path(profile)
    html = Nokogiri::HTML(response.body)
    expect(html.css(".play-row").count).to eq(50)
    get html.at_css("a[href*='before=']")["href"]
    expect(response.body).to include("Harbor Lights", "An unrecognized track")
    expect(response.body).not_to include("Paging fixture")
  end

  it "rejects writes from visitors and non-owners while preserving owner management" do
    account = fixture.fetch(:account)
    play = fixture.fetch(:resolved)
    authorize_fixture_publication(fixture)
    expect { post decide_resolution_surface_path(play) }.not_to change(RecordingResolution::Decision, :count)
    expect(response).to redirect_to(root_path)
    expect { post "#{public_profile_recording_path(profile, fixture.fetch(:recording))}/import" }
      .not_to change(CatalogImport, :count)
    expect(response).to have_http_status(:not_found)

    finish_oidc
    other = User.find_by!(oidc_subject: @subject)
    stub_request(:get, /ws.audioscrobbler.com/).to_return(body: '<lfm status="ok"><user><name>qalephd</name></user></lfm>')
    stub_const("ENV", ENV.to_h.merge("LASTFM_API_KEY" => "test-key"))
    expect { patch lastfm_account_path, params: { lastfm_username: "qalephd" } }.not_to change(UserLastfmAccount, :count)
    expect(response).to redirect_to(archive_path)
    UserLastfmAccount.create!(user: other, lastfm_account: account)
    expect { ListeningProfile.establish!(account:, owner: other, reference: "Unreviewed") }.to raise_error(ArgumentError)
    expect { profile.record_consent!(consenting_owner: other, reference: "wrong owner") }.to raise_error(ArgumentError)
    expect { post decide_resolution_surface_path(play) }.not_to change(RecordingResolution::Decision, :count)
    expect(response).to have_http_status(:forbidden)
    expect { post import_recording_path(fixture.fetch(:recording)) }.not_to change(CatalogImport, :count)
    expect(response).to have_http_status(:forbidden)

    delete session_path
    @subject = fixture.fetch(:owner).oidc_subject
    finish_oidc
    get archive_path
    expect(response.body).to include("Ownership recorded by Muzeum administration.", "Import status")
    get resolution_surface_path(play)
    expect(response).to have_http_status(:ok)
    head = RecordingResolution::Decision.find_by!(scrobble_id: play.id)
    expect { post decide_resolution_surface_path(play), params: { mode: "unresolved", scope: "scrobble", play_id: play.id,
      head: head.id, reason: "Owner review" } }
      .to change(RecordingResolution::Decision, :count).by(1)
    expect(response).to redirect_to(resolution_surface_path(play))
  end
end
