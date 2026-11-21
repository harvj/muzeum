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
    browser.execute_cdp("Emulation.setSafeAreaInsetsOverride", insets: { left: 35, right: 43, top: 6 })
    expect(browser.execute_script(<<~JS)).to eq([ 35, 43 ])
      const w = document.querySelector(".harvj-wordmark").getBoundingClientRect();
      const login = document.querySelector('header a[href="/login"]').getBoundingClientRect();
      return [Math.round(w.left), Math.round(innerWidth - login.right)];
    JS
    browser.execute_cdp("Emulation.setSafeAreaInsetsOverride", insets: {})
    expect(page).to have_link("Jim Harvey", href: "https://harvj.com")
    browser.action.send_keys(:tab).perform
    expect(page).to have_css(".shell-skip:focus")
    browser.action.send_keys(:enter).perform
    expect(page).to have_css("main:focus")
  end

  it "keeps authenticated header and open disclosure within the five Shell breakpoints and a short viewport" do
    sign_in_locally("a-long-auth-issued-name-12345678")
    browser = page.driver.browser
    [ 1440, 701, 700, 390, 320 ].each do |width|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height: 720, deviceScaleFactor: 1, mobile: width <= 700)
      expect(page).to have_css(".harvj-session > summary[aria-label^='a-long-auth']")
      expect(page).to have_link("Archive", href: archive_path)
      expect(page).to have_css(".library-nav a[aria-current='page']", text: "Archive")
      assert_identity_geometry(browser, width)
      find(".harvj-session > summary").send_keys(:enter)
      expect(page).to have_css(".harvj-session[open]")
      assert_identity_geometry(browser, width, open: true)
      find(".harvj-session > summary").send_keys(:escape)
    end

    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 320, height: 290, deviceScaleFactor: 1, mobile: true)
    browser.execute_script("document.querySelector('.session-username').style.fontSize = '200%'")
    find(".harvj-session > summary").send_keys(:enter)
    expect(page).to have_select("Appearance")
    expect(page).to have_button("Log Out")
    expect(browser.execute_script(<<~JS)).to eq([ "static", true ])
      const panel = document.querySelector(".harvj-session-panel");
      return [getComputedStyle(panel).position, document.documentElement.scrollWidth <= innerWidth];
    JS
  end

  def assert_identity_geometry(browser, width, open: false)
    values = browser.execute_script(<<~JS)
      const wordmark = document.querySelector(".harvj-wordmark");
      const trigger = document.querySelector(".harvj-session > summary");
      const panel = document.querySelector(".harvj-session-panel").getBoundingClientRect();
      const w = wordmark.getBoundingClientRect(), t = trigger.getBoundingClientRect();
      const font = getComputedStyle(wordmark);
      return [w.left, w.top, innerWidth-t.right, t.height, document.documentElement.scrollWidth,
        font.fontFamily, parseFloat(font.fontSize), Number(font.fontWeight), parseFloat(font.lineHeight),
        (w.top+w.bottom-t.top-t.bottom)/2, panel.right-t.right, panel.width, panel.top-t.bottom];
    JS
    inset, font = width > 700 ? [ width * 0.065, 24 ] : [ 28, 23 ]
    expect(values[0]).to be_within(1).of(inset)
    expect(values[1]).to be_within(1).of(width > 700 ? 35 : 27)
    expect(values[2]).to be_within(1).of(inset)
    expect(values[3]).to be >= 44
    expect(values[4]).to be <= width
    expect(values[5]).to start_with("DM")
    expect(values[6..7]).to eq([ font, 600 ])
    expect(values[8]).to be_within(0.1).of(font * 1.2)
    expect(values[9]).to be_within(1).of(0)
    if open
      expect(values[10]).to be_within(1).of(0)
      expect(values[11]).to be_within(1).of([ 300, width - 2 * inset ].min)
      expect(values[12]).to be_within(1).of(8)
    end
  end

  it "opens the identity disclosure with a verified name, preserves full keyboard access and hides revoked links" do
    name = "Jim-Harvey"
    sign_in_locally(name)
    browser = page.driver.browser
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 320, height: 640, deviceScaleFactor: 1, mobile: true)
    trigger = find(".harvj-session > summary[aria-label='#{name}']")
    expect(trigger.all("[aria-hidden=true]", count: 2).map(&:text)).to eq([ "", "⌄" ])
    expect(page).to have_no_link("Library")
    expect(accessibility_node(browser, "Library")).to be_nil
    expect(accessibility_expanded(browser, name)).to be(false)
    trigger.send_keys(:enter)
    expect(page).to have_css(".harvj-session[open]")
    expect(page).to have_link("Library", href: "https://library.harvj.com/")
    expect(page).to have_select("Appearance")
    Selenium::WebDriver::Wait.new(timeout: Capybara.default_max_wait_time).until do
      accessibility_expanded(browser, name) == true
    end
    browser.action.send_keys(:tab).perform
    expect(page).to have_css(".harvj-session-panel a:focus-visible", text: "Library")
    browser.action.key_down(:shift).send_keys(:tab).key_up(:shift).perform
    expect(page).to have_css(".harvj-session > summary:focus")
    find_link("Library").send_keys(:escape)
    expect(page).to have_no_css(".harvj-session[open]")
    expect(page).to have_css(".harvj-session > summary:focus")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)

    allow(OidcClient).to receive(:new).and_return(double(shell_evidence: nil))
    trigger.send_keys(:space)
    expect(page).to have_css(".harvj-session[open] > summary[aria-label='Signed in']")
    expect(page).to have_no_link("Library")
    expect(page).to have_button("Log Out")
    browser.execute_cdp("Input.dispatchTouchEvent", type: "touchStart", touchPoints: [ { x: 8, y: 100 } ])
    browser.execute_cdp("Input.dispatchTouchEvent", type: "touchEnd", touchPoints: [])
    expect(page).to have_no_css(".harvj-session[open]")
  end
  def accessibility_node(browser, name)
    browser.execute_cdp("Accessibility.getFullAXTree").fetch("nodes").find do |node|
      !node["ignored"] && node.dig("name", "value") == name
    end
  end

  def accessibility_expanded(browser, name)
    node = accessibility_node(browser, name)
    node&.fetch("properties")&.find { |property| property["name"] == "expanded" }&.dig("value", "value")
  end

  def sign_in_locally(name)
    evidence = { username: name, expires_at: 55.seconds.from_now.to_i, destinations: %w[continuum] }
    allow(OidcClient).to receive(:new).and_return(double(shell_evidence: evidence))
    allow(ApplicationShellRegistry).to receive(:destinations).and_return([ { name: "Library", url: "https://library.harvj.com/" } ])
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "shell-browser-subject")
    session = user.sessions.create!(expires_at: 1.hour.from_now, last_seen_at: Time.current, verified_at: Time.current,
      grant_token: "test-only-grant")
    visit root_path
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.signed[:session_id] = session.id
    page.driver.browser.manage.add_cookie(name: "session_id", value: jar[:session_id], path: "/", http_only: true)
    visit archive_path
  end
end
