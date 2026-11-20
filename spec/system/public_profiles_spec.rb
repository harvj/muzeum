require "rails_helper"
require_relative "../support/public_profile_fixture"

RSpec.describe "Public profile browsing", type: :system do
  include PublicProfileFixture

  before do
    skip "Run with BROWSER_TESTS=1 for public profile browser verification" unless ENV["BROWSER_TESTS"] == "1"

    driven_by :selenium, using: :headless_chrome do |options|
      options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
    end
  end

  it "keeps both anonymous entry points usable across desktop light and mobile dark modes" do
    fixture = listening_profile_fixture
    authorize_fixture_publication(fixture)
    browser = page.driver.browser
    allow(SiteArt).to receive(:snapshot).and_return(
      light: { url: "/environments/stone/limestone.jpg" }, dark: { url: "/environments/stone/onyx.jpg" })

    [ [ 1440, 960 ], [ 390, 844 ] ].product(%w[light dark]).each do |(width, height), theme|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width < 700)
      browser.execute_cdp("Emulation.setEmulatedMedia", features: [
        { name: "prefers-color-scheme", value: theme }, { name: "prefers-reduced-motion", value: "reduce" }
      ])
      visit root_path
      expect(page).to have_field("Last.fm username", disabled: true)
      expect(page).to have_button("Get Started", disabled: true)
      expect(page).to have_link("Open your archive", href: login_path)
      verify_navigation
      verify_viewport(width, theme)
      capture("landing-#{theme}")

      click_link "qalephd"
      expect(page).to have_content("Unresolved")
      expect(page).to have_no_link("Resolution")
      verify_navigation
      verify_viewport(width, theme)
      capture("archive-#{theme}")

      click_link "Harbor Lights"
      expect(page).to have_content("1 resolved listening observation")
      click_link "Harbor Sessions"
      expect(page).to have_content("The Empty Pier")
      expect(page).to have_no_button("Import")
      verify_navigation
      verify_viewport(width, theme)
    end
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
    browser&.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  def verify_navigation
    expect(page).to have_css('header .harvj-wordmark[href="https://muzeum.fm/"]')
    expect(page).to have_link("Jim Harvey", href: "https://harvj.com/")
    expect(page).to have_link("Log In", href: login_path)
    expect(page).to have_no_css("header summary[aria-label='Session menu']")
  end

  def verify_viewport(width, theme)
    texture = theme == "light" ? "limestone" : "onyx"
    expect(page).to have_css("img.site-art-background[src$='#{texture}.jpg']", visible: :all)
    expect(page.evaluate_script("innerWidth")).to eq(width)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true)
  end

  def capture(name)
    return unless ENV["PUBLIC_PROFILE_CAPTURES"]

    page.evaluate_async_script("const done = arguments[0]; document.fonts.ready.then(() => requestAnimationFrame(() => done(true)))")
    page.save_screenshot(File.join(ENV.fetch("PUBLIC_PROFILE_CAPTURES"), "#{name}.png"))
  end
end
