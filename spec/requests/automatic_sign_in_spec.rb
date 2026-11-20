require "rails_helper"
require_relative "../support/oidc_flow"

RSpec.describe "Canonical OIDC entry", type: :request do
  include OidcFlow
  let(:navigation) { { "Sec-Fetch-Mode" => "navigate", "Sec-Fetch-Dest" => "document" } }
  before { prepare_oidc }
  after { restore_oidc }

  def enter_application(path = archive_path)
    get path, headers: navigation
    expect(response).to have_http_status(:redirect)
    expect(URI(response.location).path).to eq(login_path)
    expect(URI(response.location).query).to include("resume=")
    expect(response.headers["Cache-Control"]).to include("no-store")
    follow_redirect!
    expect(URI(response.location).host).to eq("auth.harvj.com")
  end

  it "starts at /login and reuses a valid local session without another provider transaction" do
    get root_path
    expect(response).to have_http_status(:ok)
    expect(OidcAttempt.count).to eq(0)
    get login_path
    expect(URI(response.location).host).to eq("auth.harvj.com")
    finish_oidc(initiate: false)
    expect(response).to redirect_to(archive_path)

    expect { get login_path, headers: navigation }.not_to change(OidcAttempt, :count)
    expect(response).to redirect_to(archive_path)
  end

  it "restores the original protected page and its query through the browser-bound attempt" do
    enter_application("/artists?q=boards")
    finish_oidc(initiate: false)
    expect(response).to redirect_to("/artists?q=boards")
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(OidcAttempt.count).to eq(0)
  end

  it "ignores arbitrary destinations on /login and rejects unsafe local candidates" do
    get login_path, params: { return_to: "https://evil.example/", next: "/oidc/callback" }
    finish_oidc(initiate: false)
    expect(response).to redirect_to(archive_path)
    expect([ "//evil.example", "/archive/%2F", "/archive\\other", "/oidc/callback", "/login", "/session",
      "/archive#fragment", "/archive?x=\n" ].map { |path| LoginDestination.validate(path) }).to all(be_nil)
  end

  it "keeps a newer attempt and its destination when an older callback arrives" do
    enter_application("/artists?q=first")
    first = OidcAttempt.last
    get login_path
    second = OidcAttempt.last
    expect(first.state).not_to eq(second.state)
    get "/oidc/callback", params: { state: first.state, code: "stale" }
    expect(response).to redirect_to(root_path)
    expect(Session.count).to eq(0)

    get "/oidc/callback?state=#{second.state}&code=one&code=two"
    expect(response).to redirect_to(root_path)
    expect(OidcAttempt.exists?(second.id)).to be(false)
    expect(Session.count).to eq(0)
  end

  it "keeps separately signed protected destinations distinct across tabs" do
    get "/artists?q=first", headers: navigation
    first_entry = response.location
    get "/releases?q=second", headers: navigation
    get first_entry
    finish_oidc(initiate: false)
    expect(response).to redirect_to("/artists?q=first")
  end

  it "rejects a forged handoff and retires obsolete initiation routes" do
    get login_path(resume: "forged")
    expect(response).to redirect_to(root_path)
    expect(OidcAttempt.count).to eq(0)
    expect { Rails.application.routes.recognize_path("/session/new", method: :get) }.to raise_error(ActionController::RoutingError)
    expect { Rails.application.routes.recognize_path("/session", method: :post) }.to raise_error(ActionController::RoutingError)
  end

  %w[access_denied login_required server_error].each do |error|
    it "offers explicit retry without a loop after #{error}" do
      enter_application
      get "/oidc/callback", params: { state: OidcAttempt.last.state, error: }
      follow_redirect!
      expect(response.body).to include("Sign-in could not be verified", "Log In")
      get archive_path, headers: navigation
      expect(response).to redirect_to(root_path)
      expect(Session.count).to eq(0)
      expect(OidcAttempt.count).to eq(0)
      get login_path
      expect(URI(response.location).host).to eq("auth.harvj.com")
    end
  end

  it "keeps the public landing available through discovery outages and never starts a background attempt" do
    stub_request(:get, "https://auth.harvj.com/.well-known/openid-configuration").to_timeout
    enter = -> { get login_path, headers: navigation }
    expect(&enter).not_to change(OidcAttempt, :count)
    follow_redirect!
    expect(response.body).to include("Sign-in is temporarily unavailable")
    get archive_path, headers: navigation
    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response).to have_http_status(:ok)
  end

  it "does not create an attempt for prefetches, frames, fetches, HEAD, JSON, or background dashboard updates" do
    [ navigation.merge("Turbo-Frame" => "dashboard"), navigation.merge("Purpose" => "prefetch"),
      navigation.merge("Sec-Purpose" => "prefetch;prerender"), navigation.merge("Sec-Fetch-Mode" => "cors"),
      navigation.merge("Sec-Fetch-Dest" => "iframe"), { "X-Requested-With" => "XMLHttpRequest" } ].each do |headers|
      get(login_path, headers:)
      expect(response).to have_http_status(:no_content)
      get(archive_path, headers:)
      expect(response).to redirect_to(root_path)
    end
    head login_path, headers: navigation
    get login_path(format: :json), headers: navigation
    get dashboard_updates_path, headers: navigation
    expect(response).to redirect_to(root_path)
    expect(OidcAttempt.count).to eq(0)
  end

  it "returns to public content after logout or rate limiting" do
    enter_application
    finish_oidc(initiate: false)
    stub_request(:post, "https://auth.harvj.com/revoke").to_timeout
    delete session_path
    expect(response).to redirect_to(root_path)
    get archive_path, headers: navigation
    expect(response).to redirect_to(root_path)
    expect(Session.count).to eq(0)
    expect(OidcAttempt.count).to eq(0)

    allow(SessionsController.cache_store).to receive(:increment).and_return(11)
    get login_path, headers: navigation
    follow_redirect!
    expect(response.body).to include("Please try again later", "Log In")
    expect(OidcAttempt.count).to eq(0)
  end
end
