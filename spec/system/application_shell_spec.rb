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
end
