require "rails_helper"

RSpec.describe "Application Shell navigation", type: :system do
  before do
    skip "Run with BROWSER_TESTS=1 for browser conformance" unless ENV["BROWSER_TESTS"] == "1"

    driven_by :selenium, using: :headless_chrome do |options|
      options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
    end
  end

  it "retains local login, renders ordered links from verified evidence, and clears them on revocation" do
    visit root_path
    expect(page).to have_link("Log In", href: login_path)
    expect(page).to have_no_css(".harvj-session")
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "browser-shell-viewer")
    local_session = user.sessions.create!(expires_at: 7.days.from_now, last_seen_at: Time.current,
      verified_at: Time.current, grant_token: "browser-shell-grant")
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.signed[:session_id] = local_session.id
    page.driver.browser.manage.add_cookie(name: "session_id", value: jar[:session_id], path: "/", http_only: true)
    provider = instance_double(OidcClient)
    allow(OidcClient).to receive(:new).and_return(provider)
    evidence = { username: "alex", ids: %w[continuum-engine remote-gaming muzeum], expires_at: 50.seconds.from_now.to_i }
    allow(provider).to receive(:shell_evidence).and_return(evidence)

    [ [ 1440, 960 ], [ 701, 750 ], [ 700, 750 ], [ 390, 844 ], [ 320, 540 ] ].each do |width, height|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width <= 700)
      visit archive_path
      expect(page).to have_css(".harvj-session summary", text: "alex")
      geometry = page.evaluate_script(<<~JS)
        (() => {
          const wordmark = document.querySelector(".harvj-wordmark").getBoundingClientRect()
          const trigger = document.querySelector(".harvj-session summary").getBoundingClientRect()
          return [wordmark.left, wordmark.top, innerWidth - trigger.right, trigger.height]
        })()
      JS
      inset = width <= 700 ? 28 : width * 0.065
      expect(geometry[0]).to be_within(1).of(inset)
      expect(geometry[1]).to be_within(1).of(width <= 700 ? 27 : 35)
      expect(geometry[2]).to be_within(1).of(inset)
      expect(geometry[3]).to be >= 44
      find(".harvj-session summary").send_keys(:enter)
      within(".harvj-session-panel") do
        expect(page).to have_link("Remote-Gaming", href: "https://gaming.harvj.com/")
        expect(page).to have_link("Continuum Engine", href: "https://funding.harvj.com/")
        expect(all("[data-application-shell-target='links'] a").map(&:text)).to eq([ "Remote-Gaming", "Continuum Engine" ])
        expect(page).to have_no_link("Muzeum")
      end
      expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
      find_link("Remote-Gaming").send_keys(:escape)
      expect(page).to have_no_css(".harvj-session[open]")
      expect(page.evaluate_script("document.activeElement === document.querySelector('.harvj-session summary')")).to be(true)
    end

    allow(provider).to receive(:shell_evidence).and_raise(OidcClient::Failure)
    find(".harvj-session summary").click
    expect(page).to have_css(".harvj-session summary", text: "Signed in")
    expect(page).to have_no_link("Remote-Gaming")
    expect(page).to have_button("Log Out")
  end

  it "measures anonymous geometry and authenticates a long username for narrow touch and accessibility" do
    browser = page.driver.browser
    [ [ 1440, 800 ], [ 701, 650 ], [ 700, 600 ], [ 390, 600 ], [ 320, 460 ] ].each do |width, height|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width <= 700)
      visit root_path
      values = page.evaluate_script(<<~JS)
        (() => {
          const mark = document.querySelector('.harvj-wordmark').getBoundingClientRect()
          const login = document.querySelector('.anonymous-account-nav > a').getBoundingClientRect()
          return [mark.left, mark.top, innerWidth - login.right, login.height, document.documentElement.scrollWidth]
        })()
      JS
      expected = width <= 700 ? 28 : width * 0.065
      expect(values[0]).to be_within(1).of(expected)
      expect(values[1]).to be_within(1).of(width <= 700 ? 27 : 35)
      expect(values[2]).to be_within(1).of(expected)
      expect(values[3]).to be >= 44
      expect(values[4]).to be <= width
    end

    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "extra-shell-review-user")
    session = user.sessions.create!(expires_at: 7.days.from_now, last_seen_at: Time.current, verified_at: Time.current, grant_token: "extra-shell-review-grant")
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.signed[:session_id] = session.id
    browser.manage.add_cookie(name: "session_id", value: jar[:session_id], path: "/", http_only: true)
    provider = instance_double(OidcClient)
    allow(OidcClient).to receive(:new).and_return(provider)
    username = "alex-#{'a' * 27}"
    allow(provider).to receive(:shell_evidence).and_return(username:, ids: [], expires_at: 45.seconds.from_now.to_i)
    visit archive_path
    expect(page).to have_css(".harvj-session summary", text: username)
    tree = browser.execute_cdp("Accessibility.getFullAXTree")
    expect(tree.fetch("nodes").any? { |node| node.dig("name", "value") == username }).to be(true)
    trigger = page.evaluate_script(<<~JS)
      (() => {
        const rect = document.querySelector('.harvj-session summary').getBoundingClientRect()
        return [rect.left + rect.width / 2, rect.top + rect.height / 2]
      })()
    JS
    browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: true)
    browser.execute_cdp("Input.dispatchTouchEvent", type: "touchStart", touchPoints: [ { x: trigger[0], y: trigger[1] } ])
    browser.execute_cdp("Input.dispatchTouchEvent", type: "touchEnd", touchPoints: [])
    expect(page).to have_css(".harvj-session[open]")
    expect(page).to have_select("Appearance")
    expect(page).to have_button("Log Out")
    page.execute_script("document.documentElement.style.fontSize = '200%'")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
  end
end
