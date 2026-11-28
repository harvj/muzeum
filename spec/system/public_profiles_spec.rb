require "rails_helper"
require_relative "../support/site_art_pair"
require_relative "../support/public_profile_fixture"

RSpec.describe "Public profile browsing", type: :system do
  include PublicProfileFixture

  before do
    allow(SiteArt).to receive(:snapshot).and_return(SiteArtPair::SNAPSHOT)
    skip "Run with BROWSER_TESTS=1 for public profile browser verification" unless ENV["BROWSER_TESTS"] == "1"

    driven_by :selenium, using: :headless_chrome do |options|
      options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
    end
  end

  it "keeps both anonymous entry points usable across desktop light and mobile dark modes" do
    fixture = listening_profile_fixture
    authorize_fixture_publication(fixture)
    browser = page.driver.browser

    [ [ 1440, 960 ], [ 390, 844 ] ].product(%w[light dark]).each do |(width, height), theme|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width < 700)
      browser.execute_cdp("Emulation.setEmulatedMedia", features: [
        { name: "prefers-color-scheme", value: theme }, { name: "prefers-reduced-motion", value: "reduce" }
      ])
      visit root_path
      expect(page).to have_field("Last.fm username", disabled: true)
      expect(page).to have_button("Get Started", disabled: true)
      expect(page).to have_no_css("main .intro")
      expect(page).to have_no_link("Open your archive")
      expect(page).to have_no_select("Appearance")
      trigger = find(".shell-appearance summary[aria-label='Appearance settings']")
      expect(page.evaluate_script(<<~JS)).to be(true)
        (() => {
          const icon = document.querySelector(".shell-appearance summary").getBoundingClientRect()
          return icon.right > innerWidth - 24 && icon.bottom > innerHeight - 24
        })()
      JS
      trigger.send_keys(:enter)
      expect(page).to have_select("Appearance")
      expect(page).to have_button("Pause light")
      trigger.send_keys(:enter)
      expect(page).to have_no_select("Appearance")
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
    expect(page).to have_no_css("header .harvj-session > summary")
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
