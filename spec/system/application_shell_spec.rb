require "rails_helper"

RSpec.describe "Application Shell", type: :system do
  before do
    skip "Run with BROWSER_TESTS=1 for Shell browser verification" unless ENV["BROWSER_TESTS"] == "1"
    driven_by :selenium, using: :headless_chrome do |options|
      options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
    end
  end

  it "uses canonical header geometry, deliberate login and a keyboard skip link on anonymous pages" do
    visit root_path
    browser = page.driver.browser
    [ 1440, 701, 700, 390, 320 ].each do |width|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height: 720, deviceScaleFactor: 1, mobile: width <= 700)
      expect(page).to have_link("Log In", href: login_path)
      expect(page).to have_no_css(".harvj-session", visible: :all)
      left, top, right, height, scroll_width = browser.execute_script(<<~JS)
        const wordmark = document.querySelector(".harvj-wordmark").getBoundingClientRect();
        const login = document.querySelector('header a[href="/login"]').getBoundingClientRect();
        return [wordmark.left, wordmark.top, innerWidth - login.right, login.height, document.documentElement.scrollWidth];
      JS
      inset = width > 700 ? width * 0.065 : 28
      expect(left).to be_within(1).of(inset)
      expect(right).to be_within(1).of(inset)
      expect(top).to be_within(1).of(width > 700 ? 35 : 27)
      expect(height).to be >= 44
      expect(scroll_width).to be <= width
    end
    expect(page).to have_link("Jim Harvey", href: "https://harvj.com")
    browser.action.send_keys(:tab).perform
    expect(page).to have_css(".shell-skip:focus")
    browser.action.send_keys(:enter).perform
    expect(page).to have_css("main:focus")
  end

  it "opens the identity disclosure with a verified name, preserves full keyboard access and hides revoked links" do
    name = "an-auth-issued-username-12345678"
    evidence = { username: name, expires_at: 55.seconds.from_now.to_i, destinations: %w[continuum] }
    allow(OidcClient).to receive(:new).and_return(double(shell_evidence: evidence))
    allow(ApplicationShellRegistry).to receive(:destinations).and_return([ { name: "Library", url: "https://library.harvj.com/" } ])
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "shell-browser-subject")
    session = user.sessions.create!(expires_at: 1.hour.from_now, last_seen_at: Time.current, verified_at: Time.current,
      grant_token: "test-only-grant")
    visit root_path
    browser = page.driver.browser
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.signed[:session_id] = session.id
    browser.manage.add_cookie(name: "session_id", value: jar[:session_id], path: "/", http_only: true)
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 320, height: 640, deviceScaleFactor: 1, mobile: true)
    visit archive_path
    trigger = find(".harvj-session > summary[aria-label='#{name}']")
    expect(trigger.all("[aria-hidden=true]", count: 2).map(&:text)).to eq([ "", "⌄" ])
    expect(page).to have_no_link("Library")
    trigger.send_keys(:enter)
    expect(page).to have_css(".harvj-session[open]")
    expect(page).to have_link("Library", href: "https://library.harvj.com/")
    expect(page).to have_select("Appearance")
    find_link("Library").send_keys(:escape)
    expect(page).to have_no_css(".harvj-session[open]")
    expect(page).to have_css(".harvj-session > summary:focus")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)

    allow(OidcClient).to receive(:new).and_return(double(shell_evidence: nil))
    trigger.send_keys(:enter)
    expect(page).to have_css(".harvj-session[open] > summary[aria-label='Signed in']")
    expect(page).to have_no_link("Library")
    expect(page).to have_button("Log Out")
    browser.execute_cdp("Input.dispatchTouchEvent", type: "touchStart", touchPoints: [ { x: 8, y: 100 } ])
    browser.execute_cdp("Input.dispatchTouchEvent", type: "touchEnd", touchPoints: [])
    expect(page).to have_no_css(".harvj-session[open]")
  end
end
