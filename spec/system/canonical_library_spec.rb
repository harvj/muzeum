require "rails_helper"
require_relative "../support/catalog_fixtures"

RSpec.describe "Canonical library resolution workflow", type: :system do
  include CatalogFixtures

  before do
    skip "Run with BROWSER_TESTS=1 for canonical workspace browser verification" unless ENV["BROWSER_TESTS"] == "1"

    driven_by :selenium, using: :headless_chrome do |options|
      options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
    end
  end

  it "reviews a candidate, applies it using the keyboard, and opens the admitted track listing" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "canonical-browser", lastfm_username: "canonical-browser")
    observation = catalog_observation(user, time: Time.utc(2024, 8, 20, 20, 15))
    catalog_assessment(observation)
    sign_in(user)
    visit releases_path
    expect(page).to have_text("No canonical releases yet")
    click_link "Resolution"
    click_link "Signals"
    expect(page).to have_text("A checked MusicBrainz edition contains this track slot")
    within(".candidate", text: "Signals") do
      find_button("Apply to all").send_keys(:enter)
    end
    expect(page).to have_text("Recording decision saved.")
    expect(page).to have_text("Confirmed candidate")

    request = CatalogImport.find_by!(kind: "recording")
    expect(request.state).to eq("pending")
    session = CatalogFixtures::Session.new
    allow(RecordingResolution::ProviderSession).to receive(:new).and_return(session)
    CanonicalCatalogJob.perform_now(request.id)
    expect(request.reload.state).to eq("imported")

    click_link "Releases"
    click_link "Night Drive"
    expect(page).to have_text("Track listing")
    expect(all("tbody tr").length).to eq(3)
    expect(all(".track-number", minimum: 4).map(&:text)).to eq([ "#", "1", "2", "3" ])
    verify_appearances("release")
    find_link("Different Song").hover
    expect(inverted_link?).to be(true)
    capture_link_state("hover")
    page.execute_script("document.querySelector('h1').scrollIntoView()")
    find(".library-nav a", text: "Archive").hover
    page.execute_script("document.querySelector('.catalog-table a').focus()")
    expect(inverted_link?).to be(true)
    capture_link_state("focus")

    click_link "Different Song"
    expect(page).to have_text("0 resolved listening observations")
    expect(page).to have_link("Night Drive")
    click_button "Import"
    expect(page).to have_text("Pending enrichment")
    click_link "Artists"
    click_link "Night Lines"
    expect(page).to have_link("Different Song")
    expect(page).to have_link("Night Drive")

    visit resolution_surface_path(observation, play: observation.id)
    expect(page).to have_button("Only this time")
    expect(page).to have_text("Inherited from your exact-surface assignment")
    verify_appearances("resolution")
  end

  it "shows pending, ranked, ambiguous and resolved identities across desktop and mobile" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "resolution-preview", lastfm_username: "resolution-preview")
    observation = catalog_observation(user, time: Time.utc(2024, 8, 20, 20, 15))
    catalog_observation(user, time: 1.day.ago)
    browser = page.driver.browser
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 1440, height: 960, deviceScaleFactor: 1, mobile: false)
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [
      { name: "prefers-color-scheme", value: "light" }, { name: "prefers-reduced-motion", value: "reduce" }
    ])
    sign_in(user)
    visit resolution_surface_path(observation)
    expect(page).to have_text("Investigation pending")
    capture_resolution("pending-desktop")

    request = CatalogImport.where(kind: RecordingResolution::Investigation::KIND).sole
    CanonicalCatalog::Processor.new(request, session_factory: ->(*) { CatalogFixtures::Session.new }).call
    click_link "Refresh results"
    expect(page).to have_text("Muzeum’s recommendation")
    expect(page).to have_text("2 current observations")
    capture_resolution("ranked-desktop")

    assessment = RecordingResolution::Ledger.assessments(user).sole
    surface = RecordingResolution::Surface.find(RecordingResolution::Group.find(assessment.group_id).surface_id)
    first = assessment.evidence.fetch("verified_recording")
    alternate = first.merge("id" => CatalogFixtures::IDS[:other], "disambiguation" => "")
    evidence = { "candidates" => [ first, alternate ] }
    evidence["ranking"] = RecordingResolution::Ranking.call(surface, evidence)
    ambiguous = RecordingResolution::Assessment.create!(group_id: assessment.group_id, version: "fixture", actor: "fixture",
      digest: SecureRandom.hex(32), evidence:)
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [
      { name: "prefers-color-scheme", value: "dark" }, { name: "prefers-reduced-motion", value: "reduce" }
    ])
    visit resolution_surface_path(observation, assessment: ambiguous.id)
    expect(page).to have_text("Ambiguous")
    expect(page).to have_no_text("Muzeum’s recommendation")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
    capture_resolution("ambiguous-mobile")

    visit resolution_surface_path(observation, assessment: assessment.id)
    within(".candidate", text: "Signals") do
      find_button("Apply to all").send_keys(:enter)
    end
    expect(page).to have_text("Inherited from your exact-surface assignment")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
    capture_resolution("resolved-mobile")
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
    browser&.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  def capture_resolution(name)
    return unless ENV["P151_PREVIEW_DIR"]

    page.evaluate_async_script("const done = arguments[0]; document.fonts.ready.then(() => requestAnimationFrame(() => done(true)))")
    screenshot = page.driver.browser.execute_cdp("Page.captureScreenshot", format: "webp", quality: 88)
    File.binwrite(File.join(ENV.fetch("P151_PREVIEW_DIR"), "#{name}.webp"), Base64.decode64(screenshot.fetch("data")))
  end

  def inverted_link?
    page.evaluate_script(<<~JS)
      (() => {
        const link = document.querySelector(".catalog-table a:hover, .catalog-table a:focus-visible");
        if (!link) return false;
        const style = getComputedStyle(link);
        const normal = getComputedStyle(document.querySelector(".library-card"));
        return style.color === normal.backgroundColor && style.backgroundColor === normal.color;
      })()
    JS
  end

  def capture_link_state(state)
    return unless ENV["P13B_PREVIEW_DIR"]

    page.save_screenshot(File.join(ENV.fetch("P13B_PREVIEW_DIR"), "release-#{state}.png"))
  end

  def sign_in(user)
    session = user.sessions.create!(expires_at: 7.days.from_now, last_seen_at: Time.current, verified_at: Time.current,
      grant_token: "browser-test-fixture")
    visit new_session_path
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.signed[:session_id] = session.id
    page.driver.browser.manage.add_cookie(name: "session_id", value: jar[:session_id], path: "/", http_only: true)
  end

  def verify_appearances(section)
    [ [ "desktop", 1440, 960 ], [ "mobile", 390, 844 ] ].each do |size, width, height|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: size == "mobile")
      %w[light dark].each do |mode|
        find("summary[aria-label='Session menu']").send_keys(:enter)
        find(".appearance-submenu summary").send_keys(:enter) unless has_css?(".appearance-submenu[open]", wait: 0)
        select mode.capitalize, from: "Appearance"
        find("summary[aria-label='Session menu']").send_keys(:enter)
        expect(page.evaluate_script("document.documentElement.dataset.appearance")).to eq(mode)
        expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
        expect(page.evaluate_script(<<~JS)).to be(true)
          document.querySelector(".library-nav").getBoundingClientRect().right <=
            document.querySelector(".account-nav").getBoundingClientRect().left
        JS
        expect(page.evaluate_script(<<~'JS')).to be >= 4.5
          (() => {
            const style = getComputedStyle(document.querySelector(".library-card"));
            const luminance = rgb => rgb.match(/\d+/g).slice(0, 3).map(Number).map(v => {
              v /= 255;
              return v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4;
            }).reduce((sum, value, i) => sum + value * [.2126, .7152, .0722][i], 0);
            const pair = [luminance(style.color), luminance(style.backgroundColor)].sort((a, b) => b - a);
            return (pair[0] + .05) / (pair[1] + .05);
          })()
        JS
        if ENV["P13B_PREVIEW_DIR"]
          page.execute_script("document.documentElement.dataset.still = 'true'")
          page.save_screenshot(File.join(ENV.fetch("P13B_PREVIEW_DIR"), "#{section}-#{size}-#{mode}.png"))
        end
      end
    end
  end
end
