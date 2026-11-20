require "rails_helper"
require_relative "../support/oidc_flow"

RSpec.describe "Automatic OIDC entry", type: :request do
  include OidcFlow
  let(:navigation) { { "Sec-Fetch-Mode" => "navigate", "Sec-Fetch-Dest" => "document" } }
  before { prepare_oidc }
  after { restore_oidc }

  def enter_application(path = archive_path)
    get path, headers: navigation
    expect(response).to redirect_to(new_session_path)
    expect(response.headers["Cache-Control"]).to include("no-store")
    follow_redirect!
    expect(URI(response.location).host).to eq("auth.harvj.com")
  end

  it "enters the established state/nonce/PKCE flow and restores the dashboard destination" do
    enter_application("/archive?view=import")
    finish_oidc(initiate: false)
    expect(response).to redirect_to("/archive?view=import")
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Listening archive")
    get archive_path, headers: navigation
    expect(response).to have_http_status(:ok)
    expect(OidcAttempt.count).to eq(0)
  end

  it "does not trust a return_to parameter as a redirect destination" do
    enter_application("/archive?return_to=https://evil.example/")
    finish_oidc(initiate: false)
    expect(response).to redirect_to("/archive?return_to=https://evil.example/")
  end

  [ "access_denied", "login_required", "server_error" ].each do |error|
    it "offers manual retry without a loop after #{error}" do
      enter_application
      state = OidcAttempt.last.state
      get "/oidc/callback", params: { state: state, error: error }
      follow_redirect!
      expect(response.body).to include("Sign-in could not be verified", "Continue with harvj Auth")
      get archive_path, headers: navigation
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(Session.count).to eq(0)
      expect(OidcAttempt.count).to eq(0)
      post session_path
      expect(URI(response.location).host).to eq("auth.harvj.com")
    end
  end

  it "stops automatic retries when the provider displays its own denied or unavailable page" do
    enter_application
    get archive_path, headers: navigation
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Continue with harvj Auth")
    expect(OidcAttempt.count).to eq(1)
  end

  it "falls back manually on discovery failure without repeatedly creating attempts" do
    stub_request(:get, "https://auth.harvj.com/.well-known/openid-configuration").to_timeout
    get archive_path, headers: navigation
    follow_redirect!
    follow_redirect!
    expect(response.body).to include("Sign-in is temporarily unavailable")
    get archive_path, headers: navigation
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(OidcAttempt.count).to eq(1)
  end

  it "rejects a failed token verification and does not automatically try again" do
    enter_application
    finish_oidc(initiate: false, claims: { nonce: "wrong" })
    follow_redirect!
    expect(response.body).to include("Sign-in could not be verified")
    get archive_path, headers: navigation
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(Session.count).to eq(0)
  end

  it "keeps logout on the manual page even on subsequent dashboard navigation" do
    enter_application
    finish_oidc(initiate: false)
    delete session_path
    follow_redirect!
    expect(response.body).to include("Continue with harvj Auth")
    get archive_path, headers: navigation
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(Session.count).to eq(0)
    expect(OidcAttempt.count).to eq(0)
  end

  it "returns to a stable manual page when automatic initiation is rate limited" do
    allow(SessionsController.cache_store).to receive(:increment).and_return(11)
    get archive_path, headers: navigation
    follow_redirect!
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Please try again later", "Continue with harvj Auth")
    expect(OidcAttempt.count).to eq(0)
  end

  it "does not automatically initiate for manual, health, frame, fetch, prefetch, HEAD or JSON requests" do
    get new_session_path, headers: navigation
    expect(response).to have_http_status(:ok)
    get "/up", headers: navigation
    expect(response).to have_http_status(:ok)
    [ {}, navigation.merge("Turbo-Frame" => "dashboard"), navigation.merge("Purpose" => "prefetch"),
      navigation.merge("Sec-Purpose" => "prefetch;prerender"), navigation.merge("Sec-Fetch-Mode" => "cors"),
      navigation.merge("Sec-Fetch-Dest" => "iframe") ].each do |headers|
      get archive_path, headers: headers
      follow_redirect!
      expect(response).to have_http_status(:ok)
    end
    head archive_path, headers: navigation
    get archive_path(format: :json), headers: navigation
    get new_session_path
    expect(response).to have_http_status(:ok)
    expect(OidcAttempt.count).to eq(0)
  end
end
