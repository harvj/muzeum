require "rails_helper"
require_relative "../support/catalog_fixtures"

RSpec.describe "Canonical library resolution workflow", type: :system do
  include CatalogFixtures

  before do
    skip "Run with BROWSER_TESTS=1 for canonical workspace browser verification" unless ENV["BROWSER_TESTS"] == "1"

    stub_request(:get, "#{OidcClient::ISSUER}/.well-known/oauth-authorization-server").to_return(status: 503)

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
      find_button("Resolve 1 observation").send_keys(:enter)
    end
    expect(page).to have_text("Recording decision saved.")
    expect(page).to have_text("Confirmed candidate")

    request = CatalogImport.find_by!(kind: "recording")
    expect(request.state).to eq("pending")
    expect(page).to have_css("turbo-cable-stream-source[connected]", visible: :all)
    expect(page).to have_css(".review-catalog-context", text: "Checking supported release memberships")
    session = CatalogFixtures::Session.new
    allow(RecordingResolution::ProviderSession).to receive(:new).and_return(session)
    CanonicalCatalogJob.perform_now(request.id)
    expect(request.reload.state).to eq("imported")
    expect(page).to have_css(".review-catalog-context dl > div:last-child .review-catalog-mark.present")
    expect(page).to have_link("Night Drive", href: release_path(Release.find_by!(title: "Night Drive")))
    expect(page).to have_css(".review-candidate[open]")
    release = Release.find_by!(title: "Night Drive")
    within(".candidate", text: "Signals") { click_button "Resolve 1 observation" }
    expect(page).to have_text("Recording decision saved.")
    second_import = CatalogImport.latest("recording", request.entity_id)
    expect(second_import.id).not_to eq(request.id)
    CanonicalCatalogJob.perform_now(second_import.id)
    expect(second_import.reload.state).to eq("imported")
    expect(Release.where(title: "Night Drive").pluck(:id)).to eq([ release.id ])
    expect(page).to have_css(".review-catalog-context a[href='#{release_path(release)}']")

    click_link "Releases"
    click_link "Night Drive"
    expect(page).to have_text("Track listing")
    within("#listening-activity") do
      expect(page).to have_text("1 distinct resolved observation")
      expect(page).to have_link("Signals")
    end
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
    expect(page).to have_css("#listening-history", text: "3m estimated listening time")
    expect(page).to have_css(".artist-timeline-fill[data-listening-scale-percent-value='100.0']")
    find("#listening-history a", text: "30d").click
    expect(page).to have_text("No resolved plays in this period.")
    find("#listening-history a", text: "All").click
    expect(page).to have_css("#artist-recordings tbody tr:first-child .listening-bar[data-listening-scale-percent-value='100.0']", text: "1")
    find("#artist-recordings a", text: "Title").click
    expect(page).to have_css("#artist-recordings tbody tr:first-child", text: "Different Song")
    expect(page).to have_css("#artist-releases .listening-bar", text: "3m")
    expect(page).to have_css("#artist-releases", text: "1 play")
    visit artist_path(Artist.find_by!(name: "Night Lines"))
    verify_appearances("artist")

    visit resolution_surface_path(observation, play: observation.id)
    expect(page).to have_button("Resolve 1 observation")
    expect(page).to have_text("Resolve only this observation")
    expect(page).to have_text("Inherited from your exact-surface assignment")
    verify_appearances("resolution")
  end

  it "automatically shows pending release verification when the saved recording has no complete release evidence" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "catalog-pending", lastfm_username: "catalog-pending")
    observation = catalog_observation(user)
    catalog_assessment(observation)
    sign_in(user)
    visit resolution_surface_path(observation)
    click_button "Resolve 1 observation"
    expect(page).to have_text("Recording decision saved.")
    expect(page).to have_css("turbo-cable-stream-source[connected]", visible: :all)
    expect(page).to have_css(".review-catalog-context", text: "Checking supported release memberships")

    provider = CatalogFixtures::Session.new
    allow(provider).to receive(:edition).and_return(provider.edition.merge("media" => []))
    allow(RecordingResolution::ProviderSession).to receive(:new).and_return(provider)
    request = CatalogImport.find_by!(kind: "recording")
    CanonicalCatalogJob.perform_now(request.id)
    expect(request.reload.state).to eq("incomplete")
    expect(page).to have_css(".review-catalog-context", text: "Release verification pending")
    expect(page).to have_no_css(".review-catalog-context dl > div:last-child .review-catalog-mark.present")
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
    click_link "Refresh status"
    expect(page).to have_css(".review-candidate.recommended")
    expect(page).to have_text("2 matching observations")
    expect(page).to have_css(".review-candidate[open] .review-tracks li", count: 3)
    expect(page).to have_css(".review-candidate[open] .review-track-match", count: 2)
    expect(page).to have_text("🇺🇸 United States", normalize_ws: true)
    expect(page).to have_text("🇨🇦 Canada", normalize_ws: true)
    expect(page).to have_text("3:10")
    expect(page).to have_link("MusicBrainz release", href: "https://musicbrainz.org/release/#{CatalogFixtures::IDS[:edition]}")
    expect(page).to have_no_css(".resolution-review img")
    find(".review-score-explanation summary").send_keys(:enter)
    expect(page).to have_css(".review-score-explanation[open]", text: "A checked MusicBrainz edition contains this track slot")
    expect(page).to have_text("Scores express relative evidence strength.")
    capture_resolution("ranked-desktop")

    assessment = RecordingResolution::Ledger.assessments(user).sole
    surface = RecordingResolution::Surface.find(RecordingResolution::Group.find(assessment.group_id).surface_id)
    first = assessment.evidence.fetch("candidates").first
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
    expect(page).to have_no_css(".review-candidate.recommended")
    expect(page).to have_css(".review-candidate[open]", count: 1)
    all(".review-candidate-summary").last.send_keys(:enter)
    expect(page).to have_css(".review-candidate:nth-of-type(2)[open]")
    expect(page).to have_css(".review-candidate[open]", count: 1)
    expect(page).to have_text("The edition played is unverified.")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
    capture_resolution("ambiguous-mobile")

    visit resolution_surface_path(observation, assessment: assessment.id)
    within(".candidate", text: "Signals") do
      find_button("Resolve 2 observations").send_keys(:enter)
    end
    expect(page).to have_text("Inherited from your exact-surface assignment")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
    capture_resolution("resolved-mobile")
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
    browser&.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  it "makes the original claims and the provider failure clear on desktop and mobile" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "resolution-outage", lastfm_username: "resolution-outage")
    claims = { "track_name" => "des fleurs x stromae", "artist_name" => "Tove Lo", "album_name" => "ESTRUS" }
    observations = 4.times.map do |index|
      Scrobble.create!(user:, lastfm_account: user.source_account, played_at: index.hours.ago, payload: claims)
    end
    sign_in(user)
    visit resolution_surface_path(observations.first)
    expect(page).to have_text("Queued for background review")
    expect(page).to have_no_text("Provider calls")

    request = CatalogImport.find_by!(kind: RecordingResolution::Investigation::KIND)
    request.update!(state: "failed", attempts: 5, request_count: 5, failure: "musicbrainz throttled (503)")
    click_link "Refresh status"
    within(".review-heading") do
      expect(all("dt").map(&:text)).to eq(%w[ARTIST ALBUM])
      expect(page).to have_css("h1", exact_text: claims.fetch("track_name"))
      expect(all("dd").map(&:text)).to eq(claims.values.drop(1))
      expect(page).to have_text("4 matching observations")
    end
    expect(page).to have_text("5 recording-search attempts failed (HTTP 503).")
    expect(page).to have_button("Retry search")
    expect(page).to have_no_text("No credible candidates in the retained evidence.")

    browser = page.driver.browser
    [ [ "desktop", 1440, 960 ], [ "mobile", 390, 844 ] ].each do |size, width, height|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: size == "mobile")
      expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
      expect(page.evaluate_script(<<~JS)).to be(true)
        parseFloat(getComputedStyle(document.querySelector(".review-heading h1")).fontSize) >
        parseFloat(getComputedStyle(document.querySelector(".review-source-claims dd")).fontSize)
      JS
      capture_resolution("outage-#{size}")
    end
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  it "opens LIGHT BEAMS from any play and resolves the group while preserving an exception" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "light-beams-review", lastfm_username: "light-beams-review")
    release = JSON.parse(file_fixture("resolution/blue-lips.json").read)
    recording = release.fetch("media").first.fetch("tracks").first.fetch("recording")
    claims = { "artist_name" => "Tove Lo", "album_name" => release.fetch("title"), "track_name" => "LIGHT BEAMS" }
    make_play = ->(time) { Scrobble.create!(user:, played_at: time, payload: claims) }
    plays = [ 3.hours.ago, 2.hours.ago, 1.hour.ago ].map(&make_play)
    surface = RecordingResolution::Ledger.attach!(plays.first)
    group = RecordingResolution::Group.create!(surface_id: surface.id, version: RecordingResolution::Ledger::VERSION, claims: {})
    evidence = { "candidates" => [ recording.merge("releases" => [ release.slice("id", "title", "date", "country") ]) ],
      "review_tracklists" => { release.fetch("id") => RecordingResolution::ReviewRelease.project(release) } }
    evidence["ranking"] = RecordingResolution::Ranking.call(surface, evidence)
    RecordingResolution::Assessment.create!(group_id: group.id, version: "fixture", actor: "fixture",
      digest: SecureRandom.hex(32), evidence:)

    browser = page.driver.browser
    sign_in(user)
    plays.each do |play|
      visit resolution_surface_path(play)
      expect(page).to have_button("Resolve 3 observations")
      expect(page).to have_text("Future exact matches inherit this decision")
      expect(page).to have_css(".review-tracks li", count: 14)
    end
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 1440, height: 960, deviceScaleFactor: 1, mobile: false)
    capture_resolution("light-beams-desktop")
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
    capture_resolution("light-beams-mobile")

    alternate = Recording.create!(title: "Existing exception", mbid: SecureRandom.uuid)
    RecordingResolution::Ledger.record!(listener: user, scrobble: plays.second, scope: :scrobble, mode: "resolved",
      reason: "Existing exception", recording: alternate)
    visit resolution_surface_path(plays.second)
    expect(page).to have_css(".review-sidebar-card", text: /Individual overrides\s+1/)
    expect(page).to have_button("Resolve 2 observations")
    click_button "Resolve 2 observations"
    expect(page).to have_text("Recording decision saved.")
    expect(page).to have_css(".review-state", exact_text: "Resolved")
    expect(page).to have_css(".review-sidebar-card", text: /Inheriting group resolution\s+2/)
    expect(page).to have_css(".review-sidebar-card", text: /Still unresolved\s+0/)

    future = make_play.call(Time.current)
    expect(RecordingResolution::Ledger.effective(user).find(future.id).effective_recording_id).to eq(Recording.find_by!(mbid: recording.fetch("id")).id)
    expect(RecordingResolution::Ledger.effective(user).find(plays.second.id).effective_recording_id).to eq(alternate.id)
    visit archive_path
    expect(page).to have_link("LIGHT BEAMS", count: 3)
    expect(page).to have_link("Existing exception")
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  it "shows the three separate stored bad days identities before confirmation on desktop and mobile" do
    edition = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/releases/blue_lips.json").read)
    track = edition.fetch("media").flat_map { |medium| medium.fetch("tracks") }.find { |slot| slot["title"] == "bad days" }
    candidate = track.fetch("recording").merge("releases" => [ edition.slice("id", "title", "date") ])
    artist_id = candidate.fetch("artist-credit").first.dig("artist", "id")
    artist = Artist.create!(mbid: artist_id, name: "Tove Lo")
    recording = Recording.create!(mbid: candidate["id"], title: "bad days")
    recording.recording_artists.create!(artist:, role: :primary)
    release = Release.create!(title: edition["title"], ingested_from_release_mbid: edition["id"], catalog_verified_at: Time.current)
    release.catalog_track_slots.create!(recording:, medium: 1, position: track.fetch("position"), track_mbid: track.fetch("id"), title: track.fetch("title"))
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "bad-days-review", lastfm_username: "bad-days-review")
    play = Scrobble.create!(user:, lastfm_account: user.source_account, played_at: Time.current,
      payload: { artist_name: "Tove Lo", track_name: "bad days", album_name: edition["title"] })
    surface = RecordingResolution::Ledger.attach!(play)
    group = RecordingResolution::Group.create!(surface_id: surface.id, version: RecordingResolution::Ledger::VERSION, claims: {})
    evidence = { "candidates" => [ candidate ], "review_tracklists" => { edition["id"] => RecordingResolution::ReviewRelease.project(edition) } }
    RecordingResolution::Assessment.create!(group_id: group.id, version: "fixture", actor: "fixture", digest: SecureRandom.hex(32), evidence:)
    sign_in(user)
    browser = page.driver.browser
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: "dark" } ])
    [ [ 1440, 960, false ], [ 390, 844, true ] ].each do |width, height, mobile|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile:)
      visit resolution_surface_path(play)
      within(".review-catalog-context") do
        expect(all("dt").map { |label| label.text.delete_prefix("✓").strip }).to eq(%w[Artist Recording Release])
        expect(page).to have_css(".review-catalog-mark.present", count: 3)
        expect(page).to have_link(artist.name, href: artist_path(artist))
        expect(page).to have_link(recording.title, href: recording_path(recording))
        expect(page).to have_link(release.title, href: release_path(release))
        expect(page).to have_text("The original Last.fm release text is preserved. The edition played stays unverified.")
      end
      expect(page).to have_css(".review-track-match", text: "bad days")
      expect(page).to have_button("Resolve 1 observation")
      expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
      capture_resolution(mobile ? "bad-days-mobile" : "bad-days-desktop")
    end
    expect(RecordingResolution::Ledger.effective(user).find(play.id).effective_recording_id).to be_nil
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
    browser&.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  def capture_resolution(name, full: false)
    return unless ENV["P151_PREVIEW_DIR"]

    page.evaluate_async_script("const done = arguments[0]; document.fonts.ready.then(() => requestAnimationFrame(() => done(true)))")
    browser = page.driver.browser
    options = { format: "webp", quality: 88 }
    if full
      dimensions = browser.execute_cdp("Page.getLayoutMetrics").fetch("cssContentSize")
      options.merge!(captureBeyondViewport: true, clip: dimensions.slice("x", "y", "width", "height").merge("scale" => 1))
    end
    screenshot = browser.execute_cdp("Page.captureScreenshot", **options)
    File.binwrite(File.join(ENV.fetch("P151_PREVIEW_DIR"), "#{name}.webp"), Base64.decode64(screenshot.fetch("data")))
  end

  def inverted_link?
    page.evaluate_script(<<~JS)
      (() => {
        const link = document.querySelector(".catalog-table a:hover, .catalog-table a:focus-visible");
        if (!link) return false;
        const style = getComputedStyle(link);
        const base = document.createElement("span");
        base.style.color = "var(--card)";
        base.style.backgroundColor = "var(--surface-highlight)";
        link.appendChild(base);
        const expectedForeground = getComputedStyle(base).color;
        const expectedBackground = getComputedStyle(base).backgroundColor;
        base.remove();
        return style.color === expectedForeground && style.backgroundColor === expectedBackground;
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
    visit root_path
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.signed[:session_id] = session.id
    page.driver.browser.manage.add_cookie(name: "session_id", value: jar[:session_id], path: "/", http_only: true)
  end

  def verify_appearances(section)
    [ [ "desktop", 1440, 960 ], [ "mobile", 390, 844 ] ].each do |size, width, height|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: size == "mobile")
      %w[light dark].each do |mode|
        find(".harvj-session > summary").send_keys(:enter) unless page.has_css?(".harvj-session[open]", wait: 0)
        select mode.capitalize, from: "Appearance"
        find(".harvj-session[open] > summary").send_keys(:enter) if page.has_css?(".harvj-session[open]", wait: 0)
        expect(page.evaluate_script("document.documentElement.dataset.appearance")).to eq(mode)
        expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
        if section == "release"
          expect(page).to have_css("#listening-activity", text: "1 distinct resolved observation")
          capture_resolution("release-listening-#{size}-#{mode}")
        elsif section == "artist"
          expect(page).to have_css("#artist-recordings .listening-bar", text: "1")
          expect(page).to have_css("#artist-releases .listening-bar", text: "3m")
          table_ids = page.all("main .library-card[id]").map { |card| card[:id] }
          expect(table_ids).to include("listening-history", "artist-recordings", "artist-releases")
          page.execute_script("window.scrollTo(0, 0)")
          capture_resolution("artist-listening-#{size}-#{mode}", full: true)
        end
        expect(page.evaluate_script(<<~JS)).to be(true)
          (() => {
            const nav = document.querySelector(".library-nav").getBoundingClientRect()
            const account = document.querySelector(".account-nav").getBoundingClientRect()
            return nav.right <= account.left || nav.top >= account.bottom
          })()
        JS
        expect(page.evaluate_script(<<~'JS')).to be >= 4.5
          (() => {
            const style = getComputedStyle(document.querySelector(".library-card"));
            const canvas = document.createElement("canvas");
            canvas.width = canvas.height = 1;
            const pixel = canvas.getContext("2d", { willReadFrequently: true });
            const luminance = () => Array.from(pixel.getImageData(0, 0, 1, 1).data).slice(0, 3).map(v => {
              v /= 255;
              return v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4;
            }).reduce((sum, value, i) => sum + value * [.2126, .7152, .0722][i], 0);
            const paint = color => { pixel.fillStyle = color; pixel.fillRect(0, 0, 1, 1); };
            paint(style.color);
            const ink = luminance();
            paint(ink < .18 ? "#000" : "#fff");
            paint(style.backgroundColor);
            const pair = [ink, luminance()].sort((a, b) => b - a);
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
