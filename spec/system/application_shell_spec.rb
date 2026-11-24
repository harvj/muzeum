require "rails_helper"

RSpec.describe "Application Shell navigation", type: :system do
  before do
    skip "Run with BROWSER_TESTS=1 for browser conformance" unless ENV["BROWSER_TESTS"] == "1"

    driven_by :selenium, using: :headless_chrome do |options|
      options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
    end
  end

  it "uses route-based, theme-aware navigation with distinct hover and keyboard focus" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "navigation-states")
    session = user.sessions.create!(expires_at: 1.day.from_now, last_seen_at: Time.current,
      verified_at: Time.current, grant_token: "browser-nav-fixture")
    visit root_path
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.signed[:session_id] = session.id
    browser = page.driver.browser
    browser.manage.add_cookie(name: "session_id", value: jar[:session_id], path: "/", http_only: true)
    record = Recording.create!(title: "Navigation fixture", mbid: SecureRandom.uuid)

    [ [ 1440, 960 ], [ 390, 844 ] ].product(%w[light dark]).each do |(width, height), theme|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width < 700)
      browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: theme } ])
      visit recording_path(record)
      expect(page).to have_css('nav.library-nav span[aria-current="page"]', exact_text: "Recordings")
      expect(page).to have_no_css('nav.library-nav a[aria-current]')
      expect(page.evaluate_script(<<~JS)).to eq([ true, true, true, true ])
        (() => {
          const current = document.querySelector(".library-nav [aria-current]")
          const nav = current.parentElement
          const palette = document.documentElement
          const ink = getComputedStyle(palette).getPropertyValue("--ink")
          const card = getComputedStyle(palette).getPropertyValue("--card")
          const probe = document.createElement("span")
          probe.style.color = ink
          probe.style.backgroundColor = card
          document.body.append(probe)
          const style = getComputedStyle(current)
          const result = [style.backgroundColor === getComputedStyle(probe).color,
            style.color === getComputedStyle(probe).backgroundColor, current.tabIndex === -1,
            [...nav.children].every(item => getComputedStyle(item).textDecorationLine === "none")]
          probe.remove()
          return result
        })()
      JS
      within(".library-nav") do
        expect(page).to have_link("Archive")
        expect(page).to have_no_link("Recordings")
        find_link("Releases").hover
      end
      expect(page).to have_css(".library-nav a:hover", text: "Releases")
      expect(page.evaluate_script("getComputedStyle(document.querySelector('.library-nav a:hover')).backgroundColor")).to include("/ 0.12")
      if width > 700 && ENV["SHELL_NAV_PREVIEW_DIR"]
        page.save_screenshot(File.join(ENV.fetch("SHELL_NAV_PREVIEW_DIR"), "desktop-#{theme}-hover.png"))
      end
      within(".library-nav") { find_link("Releases").send_keys(:tab) }
      expect(page).to have_css(".library-nav a:focus-visible", text: "Artists")
      expect(page.evaluate_script(<<~JS)).to eq([ "none", "solid" ])
        (() => {
          const style = getComputedStyle(document.querySelector(".library-nav a:focus-visible"))
          return [style.textDecorationLine, style.outlineStyle]
        })()
      JS
      if ENV["SHELL_NAV_PREVIEW_DIR"]
        viewport = width > 700 ? "desktop" : "mobile"
        page.save_screenshot(File.join(ENV.fetch("SHELL_NAV_PREVIEW_DIR"), "#{viewport}-#{theme}-focus.png"))
      end
      visit archive_path
      expect(page).to have_css('nav.library-nav span[aria-current="page"]', exact_text: "Archive")
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
    evidence = { username: "alex", ids: %w[continuum-engine remote-gaming muzeum], issued_at: Time.current.to_i, expires_at: 50.seconds.from_now.to_i }
    allow(provider).to receive(:shell_evidence).and_return(evidence)

    [ [ 1440, 960 ], [ 701, 750 ], [ 700, 750 ], [ 390, 844 ], [ 320, 540 ] ].each do |width, height|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width <= 700)
      visit archive_path
      expect(page).to have_css(".harvj-session summary", text: "alex")
      geometry = page.evaluate_script(<<~JS)
        (() => {
          const wordmark = document.querySelector(".harvj-wordmark").getBoundingClientRect()
          const trigger = document.querySelector(".harvj-session summary").getBoundingClientRect()
          return [wordmark.left, wordmark.top, innerWidth - trigger.right, trigger.height,
            parseFloat(getComputedStyle(document.querySelector(".library-nav")).columnGap)]
        })()
      JS
      inset = width <= 700 ? 28 : width * 0.065
      expect(geometry[0]).to be_within(1).of(inset)
      expect(geometry[1]).to be_within(1).of(width <= 700 ? 27 : 35)
      expect(geometry[2]).to be_within(1).of(inset)
      expect(geometry[3]).to be >= 44
      expect(geometry[4]).to eq(width <= 700 ? 12 : 20)
      find(".harvj-session summary").send_keys(:enter)
      within(".harvj-session-panel") do
        expect(page).to have_link("Remote-Gaming", href: "https://gaming.harvj.com/")
        expect(page).to have_link("Continuum Engine", href: "https://funding.harvj.com/")
        expect(page).to have_css("[data-application-shell-target='links'] > a:nth-child(1)", exact_text: "Remote-Gaming")
        expect(page).to have_css("[data-application-shell-target='links'] > a:nth-child(2)", exact_text: "Continuum Engine")
        expect(page).to have_no_link("Muzeum")
      end
      expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
      find_link("Remote-Gaming").send_keys(:escape)
      expect(page).to have_no_css(".harvj-session[open]")
      expect(page.evaluate_script("document.activeElement === document.querySelector('.harvj-session summary')")).to be(true)
    end

    page.execute_script(<<~JS)
      const username = document.querySelector('[data-application-shell-target="username"]')
      window.shellUsernameChanges = []
      new MutationObserver(() => window.shellUsernameChanges.push(username.textContent))
        .observe(username, { childList: true, subtree: true })
    JS
    trigger = find(".harvj-session summary")
    2.times do
      trigger.click
      expect(page).to have_link("Remote-Gaming")
      trigger.click
      expect(page).to have_no_css(".harvj-session[open]")
    end
    expect(page.evaluate_script("window.shellUsernameChanges")).to eq([])

    allow(provider).to receive(:shell_evidence).and_return(evidence.merge(username: "renamed", ids: %w[continuum-engine]))
    trigger.click
    expect(page).to have_no_link("Remote-Gaming")
    expect(page).to have_link("Continuum Engine")
    expect(trigger).to have_text("alex")
    trigger.click

    allow(provider).to receive(:shell_evidence).and_raise(OidcClient::Failure)
    trigger.click
    expect(page).to have_no_link("Continuum Engine")
    expect(trigger).to have_text("alex")
    expect(page).to have_button("Log Out")
    expect(Session.exists?(local_session.id)).to be(true)
    trigger.click

    page.execute_script(<<~JS)
      window.originalShellFetch = window.fetch
      const originalTimeout = window.setTimeout
      window.setTimeout = (fn, delay, ...args) => originalTimeout(fn, delay === 10000 ? 80 : delay, ...args)
      window.fetch = (url, options) => new Promise((_, reject) => {
        options.signal.addEventListener("abort", () => {
          window.shellRefreshTimedOut = true
          reject(new DOMException("Aborted", "AbortError"))
        }, { once: true })
      })
    JS
    trigger.click
    expect(page).to have_no_link("Continuum Engine")
    expect(page).to have_css(".harvj-session summary", text: "alex")
    expect(page).to have_css(".harvj-session[open]")
    page.evaluate_async_script(<<~JS)
      const done = arguments[0]
      const check = () => window.shellRefreshTimedOut ? done(true) : requestAnimationFrame(check)
      check()
    JS
    expect(trigger).to have_text("alex")
    expect(Session.exists?(local_session.id)).to be(true)
    page.execute_script("window.fetch = window.originalShellFetch")
    trigger.click

    local_session.destroy!
    trigger.click
    expect(page).to have_link("Log In", href: login_path)
    expect(page).to have_no_css(".harvj-session")
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
    allow(provider).to receive(:shell_evidence).and_return(username:, ids: [], issued_at: Time.current.to_i, expires_at: 45.seconds.from_now.to_i)
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
    expect(page).to have_no_css(".harvj-session select#appearance")
    expect(page).to have_button("Log Out")
    page.execute_script("document.documentElement.style.fontSize = '200%'")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
  end
  it "keeps the account disclosure in document flow and scrollable in short viewports" do
    browser = page.driver.browser
    visit root_path
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "short-shell-viewport")
    session = user.sessions.create!(expires_at: 7.days.from_now, last_seen_at: Time.current,
      verified_at: Time.current, grant_token: "short-shell-grant")
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.signed[:session_id] = session.id
    browser.manage.add_cookie(name: "session_id", value: jar[:session_id], path: "/", http_only: true)
    provider = instance_double(OidcClient)
    allow(OidcClient).to receive(:new).and_return(provider)
    allow(provider).to receive(:shell_evidence).and_return(username: "Jim-Harvey",
      ids: %w[remote-gaming continuum-engine continuum], issued_at: Time.current.to_i, expires_at: 50.seconds.from_now.to_i)

    [ 1440, 701, 700, 390, 320 ].each do |width|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height: 240, deviceScaleFactor: 1, mobile: width <= 700)
      visit archive_path
      find(".harvj-session > summary").send_keys(:enter)
      expect(page).to have_css(".harvj-session[open]")
      expect(page).to have_link("Remote-Gaming")
      expect(page.evaluate_script(<<~JS)).to eq([ "static", "auto", true, true ])
        (() => {
          const panel = document.querySelector(".harvj-session-panel");
          const trigger = document.querySelector(".harvj-session > summary");
          const rect = panel.getBoundingClientRect();
          const style = getComputedStyle(panel);
          return [style.position, style.overflowY, rect.top >= trigger.getBoundingClientRect().bottom,
            rect.left >= 0 && rect.right <= innerWidth && rect.bottom <= innerHeight];
        })()
      JS
      logout = find_button("Log Out")
      logout.send_keys(:escape)
      expect(page).to have_no_css(".harvj-session[open]")
      expect(page.evaluate_script("document.activeElement === document.querySelector('.harvj-session summary')")).to be(true)
    end
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
