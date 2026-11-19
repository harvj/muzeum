require "rails_helper"
require_relative "../support/oidc_flow"

RSpec.describe "Shared Auth browser navigation", type: :system do
  include OidcFlow

  before do
    skip "Run with BROWSER_TESTS=1 for OIDC browser verification" unless ENV["BROWSER_TESTS"] == "1"
    driven_by :selenium, using: :headless_chrome do |options|
      options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
    end
    prepare_oidc
    @old_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    visit new_session_path
    @application_url = page.current_url.delete_suffix(new_session_path)
    ENV["OIDC_REDIRECT_URI"] = "#{@application_url}/oidc/callback"
    @authorizations = 0
    application_url = @application_url
    # A separate origin stands in for provider-owned SSO/login/access pages.
    # Token exchange still runs the real Ruby OIDC client and JWT verification.
    provider = lambda do |env|
      request = Rack::Request.new(env)
      headers = { "content-type" => "text/html" }
      if request.path == "/ce"
        [ 200, headers, [ "<a href='#{application_url}/archive'>Muzeum</a>" ] ]
      elsif request.path == "/authorize"
        @authorizations += 1 unless request.params["signed_in"]
        callback = "#{request.params.fetch('redirect_uri')}?#{URI.encode_www_form(state: request.params.fetch('state'), code: 'browser-code')}"
        if @provider_mode == :denied
          [ 403, headers, [ "Application access denied. <a href='#{application_url}/archive'>Return to Muzeum</a>" ] ]
        elsif @provider_mode == :fresh && !request.params["signed_in"]
          continuation = "#{request.path}?#{URI.encode_www_form(request.params.merge('signed_in' => 'yes'))}"
          [ 200, headers, [ "<h1>Test Auth login</h1><a href='#{ERB::Util.html_escape(continuation)}'>Sign in to test Auth</a>" ] ]
        else
          [ 302, headers.merge("location" => callback), [] ]
        end
      else
        [ 404, headers, [] ]
      end
    end
    @provider = Capybara::Server.new(provider, host: "127.0.0.1").boot
    allow_any_instance_of(OidcClient).to receive(:authorization_uri).and_wrap_original do |method, attempt|
      uri = URI(method.call(attempt))
      token = JSON::JWT.new(iss: OidcClient::ISSUER, sub: @subject, aud: "muzeum-test", iat: Time.current.to_i,
        exp: 5.minutes.from_now.to_i, nonce: @provider_mode == :failed ? "incorrect-nonce" : attempt.nonce)
      token.kid = "test"
      signed = token.sign(@signing_key, :RS256).to_s
      stub_request(:post, "https://auth.harvj.com/token").with { |request|
        body = Rack::Utils.parse_query(request.body)
        body["code_verifier"] == attempt.verifier && body["code"] == "browser-code"
      }.to_return(headers: { "Content-Type" => "application/json" }, body: { access_token: "browser-access",
        token_type: "bearer", expires_in: 300, id_token: signed, refresh_token: "browser-grant" }.to_json)
      uri.scheme = "http"
      uri.host = "127.0.0.1"
      uri.port = @provider.port
      uri.to_s
    end
  end

  after do
    if @old_env
      restore_oidc
      ActionController::Base.allow_forgery_protection = @old_forgery_protection
    end
  end

  def navigate_from_ce(mode)
    @provider_mode = mode
    visit "http://127.0.0.1:#{@provider.port}/ce"
    click_link "Muzeum"
  end

  it "reaches the dashboard from another application with an existing Auth SSO session" do
    navigate_from_ce(:sso)
    expect(page).to have_content("Observed artists")
    expect(page).to have_current_path(archive_path)
    expect(@authorizations).to eq(1)
    expect(User.sole.oidc_subject).to eq(@subject)
    page.refresh
    expect(page).to have_content("Observed artists")
    expect(@authorizations).to eq(1)
  end

  it "allows provider-owned fresh login before returning to the dashboard" do
    navigate_from_ce(:fresh)
    expect(page).to have_content("Test Auth login")
    click_link "Sign in to test Auth"
    expect(page).to have_content("Observed artists")
    expect(@authorizations).to eq(1)
  end

  it "does not loop after provider-owned access denial" do
    navigate_from_ce(:denied)
    expect(page).to have_content("Application access denied")
    click_link "Return to Muzeum"
    expect(page).to have_button("Continue with harvj Auth")
    expect(@authorizations).to eq(1)
    expect(Session.count).to eq(0)
  end

  it "offers manual retry after failed authentication" do
    navigate_from_ce(:failed)
    expect(page).to have_content("Sign-in could not be verified")
    visit "#{@application_url}/archive"
    expect(page).to have_button("Continue with harvj Auth")
    expect(@authorizations).to eq(1)
    expect(Session.count).to eq(0)
  end

  it "logs out without immediately starting a new provider session" do
    navigate_from_ce(:sso)
    expect(page).to have_content("Observed artists")
    find("summary[aria-label='Session menu']").click
    click_button "Log out"
    expect(page).to have_button("Continue with harvj Auth")
    visit "#{@application_url}/archive"
    expect(page).to have_button("Continue with harvj Auth")
    expect(@authorizations).to eq(1)
    expect(Session.count).to eq(0)
  end
end
