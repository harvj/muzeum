require "rails_helper"
require_relative "../support/oidc_flow"
require_relative "../support/public_profile_fixture"

RSpec.describe "Shared Auth browser navigation", type: :system do
  include OidcFlow
  include PublicProfileFixture

  before do
    skip "Run with BROWSER_TESTS=1 for OIDC browser verification" unless ENV["BROWSER_TESTS"] == "1"
    driven_by :selenium, using: :headless_chrome do |options|
      options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
    end
    prepare_oidc
    stub_request(:get, "#{OidcClient::ISSUER}/.well-known/oauth-authorization-server").to_return(status: 503)
    @old_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    visit root_path
    @application_url = page.current_url.delete_suffix("/")
    ENV["OIDC_REDIRECT_URI"] = "#{@application_url}/oidc/callback"
    @authorizations = 0
    application_url = @application_url
    # A separate origin stands in for provider-owned SSO/login/access pages.
    # Token exchange still runs the real Ruby OIDC client and JWT verification.
    provider = lambda do |env|
      request = Rack::Request.new(env)
      headers = { "content-type" => "text/html" }
      if request.path == "/auth-account"
        [ 200, headers, [ "<a href='#{application_url}/login'>Muzeum</a>" ] ]
      elsif request.path == "/ce"
        [ 200, headers, [ "<a href='#{application_url}/archive'>Muzeum</a>" ] ]
      elsif request.path == "/authorize"
        @authorizations += 1 unless request.params["signed_in"] || request.params["mfa_complete"]
        callback = "#{request.params.fetch('redirect_uri')}?#{URI.encode_www_form(state: request.params.fetch('state'), code: 'browser-code')}"
        if @provider_mode == :denied
          [ 403, headers, [ "Application access denied. <a href='#{application_url}/archive'>Return to Muzeum</a>" ] ]
        elsif @provider_mode == :mfa && !request.params["mfa_complete"]
          continuation = "#{request.path}?#{URI.encode_www_form(request.params.merge('mfa_complete' => 'yes'))}"
          [ 200, headers, [ "<h1>Test Auth MFA</h1><a href='#{ERB::Util.html_escape(continuation)}'>Complete test MFA</a>" ] ]
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
        exp: 5.minutes.from_now.to_i, nonce: @provider_mode == :failed ? "incorrect-nonce" : attempt.nonce,
        acr: ("urn:harvj:assurance:mfa" if @provider_mode == :mfa))
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
    expect(page).to have_link("Archive summary")
    expect(page).to have_current_path(archive_path)
    expect(@authorizations).to eq(1)
    expect(User.sole.oidc_subject).to eq(@subject)
    page.refresh
    expect(page).to have_link("Archive summary")
    expect(@authorizations).to eq(1)
  end

  it "returns from the Auth account through Muzeum and preserves signed-in navigation across viewports and appearances" do
    fixture = listening_profile_fixture
    authorize_fixture_publication(fixture)
    @provider_mode = :sso
    visit "http://127.0.0.1:#{@provider.port}/auth-account"
    click_link "Muzeum"
    expect(page).to have_current_path(archive_path)
    expect(@authorizations).to eq(1)
    visit "http://127.0.0.1:#{@provider.port}/auth-account"
    click_link "Muzeum"
    expect(page).to have_current_path(archive_path)
    expect(@authorizations).to eq(1)

    browser = page.driver.browser
    [ [ 1440, 960 ], [ 390, 844 ] ].product(%w[light dark]).each do |(width, height), theme|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width < 700)
      browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: theme } ])
      [ root_path, archive_path, public_profile_path(fixture.fetch(:profile)) ].each do |path|
        visit path
        expect(page).to have_css('header .harvj-wordmark[href="https://muzeum.fm/"]')
        expect(page).to have_link("Jim Harvey", href: "https://harvj.com/")
        expect(page).to have_css("header .harvj-session > summary", text: "Signed in")
        expect(page).to have_no_link("Log In")
        expect(page.evaluate_script("innerWidth")).to eq(width)
      end
    end
    expect(@authorizations).to eq(1)
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
    browser&.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  it "allows provider-owned fresh login before returning to the dashboard" do
    navigate_from_ce(:fresh)
    expect(page).to have_content("Test Auth login")
    click_link "Sign in to test Auth"
    expect(page).to have_link("Archive summary")
    expect(@authorizations).to eq(1)
  end

  it "lets Auth own MFA and completes the same Muzeum attempt with the approved assurance" do
    @provider_mode = :mfa
    ENV["OIDC_REQUIRED_ACR"] = "urn:harvj:assurance:mfa"
    visit root_path
    click_link "Log In"
    expect(page).to have_text("Test Auth MFA")
    expect(Session.count).to eq(0)
    click_link "Complete test MFA"
    expect(page).to have_current_path(archive_path)
    expect(Session.count).to eq(1)
    expect(@authorizations).to eq(1)
  end

  it "does not loop after provider-owned access denial" do
    navigate_from_ce(:denied)
    expect(page).to have_content("Application access denied")
    click_link "Return to Muzeum"
    expect(page).to have_link("Log In", href: login_path)
    expect(@authorizations).to eq(1)
    expect(Session.count).to eq(0)
  end

  it "offers manual retry after failed authentication" do
    navigate_from_ce(:failed)
    expect(page).to have_content("Sign-in could not be verified")
    visit "#{@application_url}/archive"
    expect(page).to have_link("Log In", href: login_path)
    expect(@authorizations).to eq(1)
    expect(Session.count).to eq(0)
  end

  it "logs out without immediately starting a new provider session" do
    navigate_from_ce(:sso)
    expect(page).to have_link("Archive summary")
    find(".harvj-session > summary").click
    click_button "Log Out"
    expect(page).to have_link("Log In", href: login_path)
    visit "#{@application_url}/archive"
    expect(page).to have_link("Log In", href: login_path)
    expect(@authorizations).to eq(1)
    expect(Session.count).to eq(0)
  end
end
