require "rails_helper"
require_relative "../support/site_art_pair"

RSpec.describe "Application Shell v2 appearance control", type: :system, if: ENV["BROWSER_TESTS"] == "1" do
  before do
    driven_by :selenium, using: :headless_chrome do |options|
      options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
    end
  end

  it "applies the shared geometry and preserves appearance across session and surface changes" do
    fixtures = path = ENV.fetch("APPLICATION_SHELL_FIXTURES") { file_fixture("application_shell/v2.json") }
    fixtures = JSON.parse(File.read(path)).fetch("baseline_cases").fetch("SH-06").fetch("theme_control")
    snapshot = SiteArtPair::SNAPSHOT
    allow(SiteArt).to receive(:snapshot) { snapshot }
    browser = page.driver.browser
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: "light" } ])
    visit root_path
    capture_shell("anonymous-desktop-light", 1440, 900)
    assert_geometry(fixtures)
    find(".shell-appearance summary").send_keys(:enter)
    select "Dark", from: "Appearance"
    expect_dark_pair
    find("#appearance").send_keys(:escape)
    expect(page).to have_css(".shell-appearance summary:focus")
    expect(page).to have_no_select("Appearance")
    visit root_path
    expect_dark_pair

    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "shell-v2-appearance", lastfm_username: "shell-v2-appearance")
    session = user.sessions.create!(expires_at: 1.hour.from_now, verified_at: Time.current,
      last_seen_at: Time.current, grant_token: "test-grant")
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.signed[:session_id] = session.id
    browser.manage.add_cookie(name: "session_id", value: jar[:session_id], path: "/", http_only: true)
    visit archive_path
    expect_dark_pair
    assert_geometry(fixtures)
    find(".harvj-session summary").send_keys(:enter)
    expect(page).to have_no_css(".harvj-session #appearance", visible: :all)
    expect(page).to have_button("Log Out")

    fixtures.fetch("availability_cases").each do |entry|
      snapshot = SiteArtPair::SNAPSHOT.slice(*entry.fetch("approved_modes").map(&:to_sym))
      visit archive_path
      expect(page).to have_css(".shell-appearance summary", count: entry.fetch("count"))
      expect(page.evaluate_script("localStorage.getItem('muzeum-appearance')")).to eq("dark")
      if entry.fetch("approved_modes") == [ "light" ]
        expect(page).to have_css("img.site-art-background[src*='limestone']", visible: :all)
        expect(page).to have_css("header[style*='#292D2C']")
      end
    end

    snapshot = { light: SiteArtPair::LIGHT, dark: { url: SiteArtPair::DARK.fetch(:url) } }
    visit archive_path
    expect(page).to have_no_css(".shell-appearance summary")
    expect(page).to have_css("img.site-art-background[src*='limestone']", visible: :all)
    expect(page.evaluate_script("localStorage.getItem('muzeum-appearance')")).to eq("dark")

    snapshot = SiteArtPair::SNAPSHOT
    visit archive_path
    expect_dark_pair
    browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: true)
    x, y = page.evaluate_script(<<~JS)
      (() => {
        const rect = document.querySelector(".shell-appearance summary").getBoundingClientRect();
        return [rect.left + rect.width / 2, rect.top + rect.height / 2];
      })()
    JS
    browser.execute_cdp("Input.dispatchTouchEvent", type: "touchStart", touchPoints: [ { x:, y: } ])
    browser.execute_cdp("Input.dispatchTouchEvent", type: "touchEnd", touchPoints: [])
    expect(page).to have_select("Appearance", selected: "Dark")
    capture_shell("signed-in-mobile-dark", 390, 740)
    find(".shell-appearance summary").send_keys(:escape)
    find(".harvj-session summary").send_keys(:enter)
    click_button "Log Out"
    expect(page).to have_link("Log In")
    expect_dark_pair
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
    browser&.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  def capture_shell(name, width, height)
    return unless (directory = ENV["SHELL_DESIGN_SCREENSHOTS"])

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width <= 700)
    FileUtils.mkdir_p(directory)
    page.save_screenshot(File.join(directory, "#{name}.png"))
  end

  def expect_dark_pair
    expect(page).to have_css("img.site-art-background[src*='onyx']", visible: :all)
    expect(page).to have_css("header[style*='#F1F2ED']")
  end

  def assert_geometry(fixtures)
    fixtures.fetch("viewports_css_px").each do |width|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height: 240,
        deviceScaleFactor: 1, mobile: width <= 700)
      expect(page).to have_css(".shell-appearance summary[aria-label='Appearance settings']", count: 1)
      bounds = page.evaluate_script(<<~JS)
        (() => {
          const target = document.querySelector(".shell-appearance summary").getBoundingClientRect();
          // Fixed edges use the CSS viewport excluding any classic scrollbar.
          const viewport = document.documentElement;
          return [target.width, target.height, viewport.clientWidth - target.right, viewport.clientHeight - target.bottom];
        })()
      JS
      expect(bounds).to eq([ 44, 44, 12, 12 ])
    end
  end
end
