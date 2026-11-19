require "rails_helper"
require "base64"

RSpec.describe "Dashboard appearance", type: :system do
  before do
    skip "Run with BROWSER_TESTS=1 for responsive browser verification" unless ENV["BROWSER_TESTS"] == "1"
    driven_by :selenium, using: :headless_chrome do |options|
      options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
    end
  end

  it "renders persisted observations in both modes and sizes with isolated session navigation" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "visual-test-fixture", lastfm_username: "fixture-listener")
    3.times { |i| user.scrobbles.create!(played_at: Time.utc(2020 + i, 3, 12), payload: { artist_name: "Fixture artist", album_name: "Fixture album", track_name: "Fixture track #{i}" }) }
    user.import_runs.create!(source_username: user.lastfm_username, status: :completed, scrobbles_processed: 3,
      next_page: 2, total_pages: 1, last_success_at: Time.current)
    session = user.sessions.create!(expires_at: 7.days.from_now, last_seen_at: Time.current, verified_at: Time.current, grant_token: "test-only-grant")
    visit new_session_path
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.signed[:session_id] = session.id
    page.driver.browser.manage.add_cookie(name: "session_id", value: jar[:session_id], path: "/", http_only: true)
    visit archive_path
    expect(page).to have_content("fixture-listener")
    expect(page).to have_content("Observed artists")
    expect(page).to have_css(".listening-day", count: 3)
    expect(page).to have_content("© 2026 Jim Harvey")
    observation = user.scrobbles.order(:played_at).last
    expect(page).to have_link("Fixture track 2", href: resolution_surface_path(observation, play: observation.id))
    output = Pathname(ENV.fetch("P14_PREVIEW_DIR", Rails.root.join("docs/p1.1d/previews")))
    FileUtils.mkdir_p(output) if ENV["CAPTURE_PREVIEWS"] == "1"
    [ [ "desktop", 1440, 960 ], [ "mobile", 390, 844 ] ].each do |size, width, height|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: size == "mobile")
      %w[light dark].each do |mode|
        find("summary[aria-label='Session menu']").send_keys(:enter)
        if size == "desktop"
          find(".appearance-submenu summary").hover
          expect(page).to have_css(".appearance-submenu[open]")
          expect(page.evaluate_script(<<~JS)).to be(true)
            document.querySelector(".appearance-submenu .controls").getBoundingClientRect().right <=
              document.querySelector(".appearance-submenu summary").getBoundingClientRect().left
          JS
          page.save_screenshot(output.join("desktop-appearance-menu.png")) if ENV["CAPTURE_PREVIEWS"] == "1"
        else
          find(".appearance-submenu summary").send_keys(:enter) unless has_css?(".appearance-submenu[open]", wait: 0)
        end
        select mode.capitalize, from: "Appearance"
        find("summary[aria-label='Session menu']").send_keys(:enter)
        expect(page.evaluate_script("document.documentElement.dataset.appearance")).to eq(mode)
        page.execute_script("document.documentElement.dataset.still = 'true'")
        page.execute_script("return document.fonts.ready")
        expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
        expect(page.evaluate_script("getComputedStyle(document.querySelector('.card')).borderRadius")).to eq("5px")
        page.save_screenshot(output.join("#{size}-#{mode}.png")) if ENV["CAPTURE_PREVIEWS"] == "1"
      end
    end
    # A committed source page updates an already-open authenticated dashboard.
    import = user.import_runs.create!(source_username: user.source_account.username, upper_bound: Time.current.to_i, actor_kind: "user")
    client = double("synthetic source", recent_tracks: "<lfm status='ok'><recenttracks user='fixture-listener' page='1' totalPages='1' total='1'><track><artist>New artist</artist><name>New completion</name><album>Album</album><date uts='1700000000'/></track></recenttracks></lfm>")
    Lastfm::HistoricalImporter.new(import, client: client).page!
    using_wait_time 15 do
      within(".stat", text: "Imported scrobbles") { expect(page).to have_content("4") }
      expect(page).to have_link("New completion")
    end
    find("summary[aria-label='Session menu']").click
    expect(page).to have_link("Continuum Engine", href: "https://funding.harvj.com/")
    expect(page).to have_link("Auth", href: "https://auth.harvj.com/")
    expect(page).not_to have_link("Muzeum", href: "https://muzeum.fm/")
    expect(page).not_to have_link("User management")
    page.save_screenshot(output.join("mobile-session-menu.png")) if ENV["CAPTURE_PREVIEWS"] == "1"
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.stone-environment'), '::after').animationName")).to eq("none")
    click_button "Log out"
    expect(page).to have_content("Sign in to Muzeum")
    visit archive_path
    expect(page).to have_current_path(new_session_path)
  end
end
