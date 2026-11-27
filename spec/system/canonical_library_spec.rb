require "rails_helper"
require_relative "../support/site_art_pair"
require_relative "../support/catalog_fixtures"
require_relative "../support/guilt_show_fixture"
require_relative "../support/narrow_stairs_fixture"
require_relative "../support/lady_wood_fixture"
require_relative "../support/interpol_membership_fixture"
require_relative "../support/leisure_configurations_fixture"
require_relative "../support/queen_short_track_fixture"

RSpec.describe "Canonical library resolution workflow", type: :system do
  include CatalogFixtures
  include GuiltShowFixture
  include NarrowStairsFixture
  include InterpolMembershipFixture
  include LeisureConfigurationsFixture
  include QueenShortTrackFixture

  before do
    skip "Run with BROWSER_TESTS=1 for canonical workspace browser verification" unless ENV["BROWSER_TESTS"] == "1"

    stub_request(:get, "#{OidcClient::ISSUER}/.well-known/oauth-authorization-server").to_return(status: 503)

    allow(SiteArt).to receive(:snapshot).and_return(SiteArtPair::SNAPSHOT)

    driven_by :selenium, using: :headless_chrome do |options|
      options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
    end
  end

  it "reviews a Queen of the Clouds interlude without changing observed listening in both layouts" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "queen-short-track", lastfm_username: "queen-short-track")
    release, = queen_short_track_fixture(user)
    sign_in(user)
    browser = page.driver.browser
    [ [ 1440, 960, "desktop", "Confirm inferred listen", "confirmed" ],
      [ 390, 844, "mobile", "Reject inference", "rejected" ] ].each do |width, height, size, action, decision|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: size == "mobile")
      visit release_path(release)
      find("summary", text: "Review possible unscrobbled tracks").send_keys(:enter)
      expect(page).to have_text("Timebomb → The Love (interlude) → Moments")
      click_button action
      expect(page).to have_text("Inference review saved.")
      find("summary", text: "Review possible unscrobbled tracks").send_keys(:enter)
      expect(page).to have_text("Latest decision: #{decision}")
      expect(page).to have_text("2 distinct resolved observations")
      expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
      if ENV["QUEEN_INFERENCE_CAPTURES"]
        find("#short-track-inference").scroll_to(:top)
        page.save_screenshot(File.join(ENV.fetch("QUEEN_INFERENCE_CAPTURES"), "queen-inference-#{size}.png"))
      end
    end
    expect(Scrobble.count).to eq(2)
    expect(ShortTrackInferenceDecision.order(:id).pluck(:decision)).to eq(%w[confirmed rejected])
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  it "switches verified Leisure configurations and uses their dates in catalog filters" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "leisure-review", lastfm_username: "leisure-review")
    data = JSON.parse(Rails.root.join("docs/design/release-configurations/tracklists.json").read)
    editions = data.fetch("leisure_editions").index_by { |edition| edition.fetch("date") }
    release = Release.create!(title: "Leisure", release_group_mbid: editions.fetch("1991-08-27").fetch("release_group"),
      release_year: 1991, release_month: 8, release_day: 27, catalog_verified_at: Time.current)
    %w[1991-08-27 1991-09-24 1991-09-20].each do |date|
      ReleaseConfiguration.retain!(release, source_edition(editions.fetch(date)), provenance: { "fixture" => "Leisure" })
    end
    us_track = editions.fetch("1991-09-24").dig("media", 0, "tracks", 3)
    artist = Artist.create!(name: "Blur", mbid: "ba853904-ae25-4ebb-89d6-c44cfbd71bd2")
    release.artists << artist
    recording = Recording.create!(title: us_track.fetch("title"), mbid: us_track.fetch("recording_mbid"), duration_ms: us_track.fetch("length"))
    observation = Scrobble.create!(user:, lastfm_account: user.source_account, played_at: 2.days.ago,
      payload: { artist_name: "Blur", track_name: recording.title, album_name: "Leisure" })
    RecordingResolution::Ledger.record!(listener: user, scrobble: observation, scope: :surface, mode: "resolved",
      reason: "Disposable configuration acceptance", recording:)
    sign_in(user)
    browser = page.driver.browser
    [ [ 1440, 960, "desktop", "1991-09-24", "September 24, 1991" ],
      [ 390, 844, "mobile", "1991-09-20", "September 20, 1991" ] ].each do |width, height, size, date, label|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: size == "mobile")
      visit release_path(release)
      find("summary", text: "Compare release configurations").send_keys(:enter)
      find("summary", text: date).click
      within(find("summary", text: date).find(:xpath, "..")) { click_button "Prefer this configuration" }
      expect(page).to have_css("h1 time", text: label)
      expect(page).to have_css(".release-tracks tbody tr", count: editions.fetch(date).dig("media", 0, "tracks").size)
      expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
      if ENV["LEISURE_CAPTURES"]
        page.save_screenshot(File.join(ENV.fetch("LEISURE_CAPTURES"), "leisure-#{size}.png"))
      end
      visit releases_path(release_month: "1991-09", sort: "release_date")
      expect(page).to have_link("Leisure")
    end
    visit release_path(release)
    find("summary", text: "Compare release configurations").click
    click_button "Use admitted base"
    expect(page).to have_css("h1 time", text: "August 27, 1991")
    visit releases_path(release_month: "1991-09")
    expect(page).to have_no_link("Leisure")
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  it "shows only admitted Interpol tracks as listening choices on desktop and mobile" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "interpol-membership", lastfm_username: "interpol-membership")
    play, = interpol_membership_fixture(user)
    sign_in(user)
    visit resolution_surface_path(play)
    click_button "Resolve this observation"
    expect(page).to have_text("Recording decision saved.")
    release = Release.sole
    browser = page.driver.browser
    [ [ 1440, 960 ], [ 390, 844 ] ].each do |width, height|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width == 390)
      visit release_path(release, edition_tracks: "1")
      expect(page).to have_css(".release-tracks:not(.additional-track-table) tbody tr", count: 11)
      expect(page).to have_css(".additional-track-table tbody tr", text: "Mind Over Time", count: 1)
      expect(page).to have_css(".additional-track-table input[type=checkbox]", count: 1)
      expect(page).to have_css("details:not([open]) > summary", text: "Alternative edition evidence")
      expect(page).to have_no_button("Admit additional recording")
      expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
      capture_resolution("interpol-membership-#{width == 390 ? 'mobile' : 'desktop'}", full: true)
    end
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  it "keeps the three production-derived release cases separate from canonical admission" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "release-provenance", lastfm_username: "release-provenance")
    sign_in(user)
    browser = page.driver.browser
    cases = {
      "queen" => [ "Tove Lo", "Thousand Miles", "Queen of the Clouds" ],
      "interpol" => [ "Interpol", "Pace Is the Trick", "Our Love to Admire" ],
      "songs-ohia" => [ "Songs: Ohia", "Tenskwatawa", "Songs: Ohia" ]
    }
    cases.each do |name, (artist, title, album)|
      evidence = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/release_provenance/#{name}.json").read)
      play = Scrobble.create!(user:, lastfm_account: user.source_account, played_at: Time.current,
        payload: { artist_name: artist, track_name: title, album_name: album })
      surface = RecordingResolution::Ledger.attach!(play)
      group = RecordingResolution::Group.create!(surface_id: surface.id, version: RecordingResolution::Ledger::VERSION, claims: {})
      RecordingResolution::Assessment.create!(group_id: group.id, version: "fixture", actor: "fixture",
        digest: SecureRandom.hex(32), evidence:)
      if name == "queen"
        data = evidence.fetch("construction_editions").find { |edition| edition["id"].start_with?("9cd3b250") }
        request = CatalogImport.create!(kind: "release_construction", state: "imported", entity_id: 0, due_at: Time.current)
        store = CanonicalCatalog::Store.new(request, Struct.new(:provenance).new([]))
        Release.transaction { store.release(data, CanonicalCatalog::Edition.new(data, data["id"]).slots) }
      end
      original = [ Release.count, Recording.count, RecordingSourceDecision.count, play.reload.payload ]
      [ [ 1440, 960 ], [ 390, 844 ] ].each do |width, height|
        browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width == 390)
        visit resolution_surface_path(play, candidate: evidence.fetch("candidates").sole.fetch("id"))
        expect(page).to have_css(".release-provenance:not([open]) > summary")
        if name == "queen"
          expect(page).to have_css('section[aria-label="Established canonical release"]', count: 1)
          within('section[aria-label="Established canonical release"]') do
            expect(page).to have_text("September 24, 2014")
            expect(page).to have_css(".review-tracks li", count: 16)
            expect(page).to have_css(".review-track-match", text: "Thousand Miles")
          end
          expect(page).to have_no_css('section[aria-label="Original release"]')
        else
          find(".release-provenance > summary").click
          if name == "interpol"
            expect(page).to have_text("Unclassified additional material")
            find(".release-provenance a", text: /Pace Is the Trick.*instrumental/i).click
            expect(page).to have_text("Medium 2 (CD-R) · Track 7")
          else
            expect(page).to have_no_text("Distinct program for separate review")
            within(".release-provenance") { click_link "Greenbrier" }
            expect(page).to have_text("Original publication is unverified")
            expect(page).to have_button("Investigate track provenance")
          end
        end
        expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
        capture_resolution("#{name}-#{width == 390 ? 'mobile' : 'desktop'}", full: true)
      end
      expect([ Release.count, Recording.count, RecordingSourceDecision.count, play.reload.payload ]).to eq(original)
    end
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  it "aligns neutral and inherited badges and presents release dates at verified precision" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "entity-headings")
    artist = Artist.create!(name: "Tove Lo", country: "SE", mbid: SecureRandom.uuid)
    collaborator = Artist.create!(name: "Collaborating Artist", mbid: SecureRandom.uuid)
    release = Release.create!(title: "ESTRUS", release_year: 2026, release_month: 9, release_day: 18)
    recording = Recording.create!(title: "source of life", mbid: SecureRandom.uuid)
    release.artists << [ artist, collaborator ]
    recording.artists << [ artist, collaborator ]
    sign_in(user)

    browser = page.driver.browser
    [ [ 1440, 960 ], [ 390, 844 ] ].product(%w[light dark]).each do |(width, height), theme|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width < 700)
      browser.execute_cdp("Emulation.setEmulatedMedia", features: [
        { name: "prefers-color-scheme", value: theme }, { name: "prefers-reduced-motion", value: "reduce" }
      ])
      { artist: artist_path(artist), recording: recording_path(recording), release: release_path(release) }.each do |entity, path|
        visit path
        within(".catalog-heading") do
          expect(page).to have_no_link(entity.to_s.pluralize.capitalize)
          expect(page).to have_no_link("MusicBrainz artist")
          expect(page).to have_text("Sweden") if entity == :artist
          expect(page).to have_css('h1 time[datetime="2026-09-18"]', text: "September 18, 2026") if entity == :release
          expect(page).to have_link("Collaborating Artist") if entity != :artist
        end
        geometry = page.evaluate_script(<<~JS)
          (() => {
            const badge = document.querySelector(".catalog-heading .identity-swatch")
            const box = badge.getBoundingClientRect()
            return [getComputedStyle(badge).backgroundImage, box.width, box.height,
              document.documentElement.scrollWidth <= innerWidth]
          })()
        JS
        expect(geometry[0]).to match(/linear-gradient\(to (?:right bottom|bottom right)/)
        expect(geometry[1]).to be > 14
        expect(geometry[1]).to eq(geometry[2])
        expect(geometry[3]).to be(true)
        capture_resolution("heading-#{entity}-#{width}-#{theme}")
        decision = MusicalIdentityDecision.create!(entity: artist, user:, colors: %w[pink gray])
        visit path
        expect(page).to have_css('.catalog-heading[data-identity-first="pink"][data-identity-second="gray"]')
        gradients, offset, width_px, radius = page.evaluate_script(<<~JS)
          (() => {
            const heading = document.querySelector(".catalog-heading")
            const accent = getComputedStyle(heading, "::after")
            return [[getComputedStyle(heading).backgroundImage, accent.backgroundImage,
              getComputedStyle(heading.querySelector(".identity-swatch")).backgroundImage],
              accent.left, parseFloat(accent.width), accent.borderTopLeftRadius]
          })()
        JS
        expect(gradients).to all(match(/linear-gradient\(to (?:right bottom|bottom right).*50%.*50%/))
        expect(offset).to eq("0px")
        expect(width_px).to be_within(0.1).of(9.6)
        expect(radius).to eq("8px")
        capture_resolution("colored-heading-#{entity}-#{width}-#{theme}")
        decision.destroy!
      end
      page.execute_script("document.querySelector('main').style.minHeight = '200vh'; scrollTo(0, 250)")
      expect(page).to have_css("main[data-shell-fading]")
      expect(page.evaluate_script("document.querySelector('header').getBoundingClientRect().top")).to eq(0)
      expect(page.evaluate_script("getComputedStyle(document.querySelector('main')).maskImage")).to include("linear-gradient")
      capture_resolution("sticky-header-#{width}-#{theme}")
    end

    [ [ 2026, 9, "September 2026" ], [ 2026, nil, "2026" ], [ nil, nil, nil ] ].each do |year, month, label|
      release.update!(release_year: year, release_month: month, release_day: nil)
      visit release_path(release)
      if label
        expect(page).to have_css(".catalog-heading time", exact_text: label)
      else
        expect(page).to have_no_css(".catalog-heading time")
      end
    end
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
    browser&.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  it "shares independently grouped listening history and keyboard-accessible details across entity pages" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "entity-history", lastfm_username: "entity-history")
    artist = Artist.create!(name: "Charli xcx", mbid: SecureRandom.uuid)
    release = Release.create!(title: "Charli", release_year: 2019, catalog_verified_at: Time.current)
    recording = Recording.create!(title: "Next Level Charli", mbid: SecureRandom.uuid, duration_ms: 158_000)
    recording.artists << artist
    release.artists << artist
    release.catalog_track_slots.create!(recording:, title: recording.title, medium: 1, position: 1, track_mbid: SecureRandom.uuid)
    MusicalIdentityDecision.create!(entity: artist, user:, colors: %w[light-green blue])
    ReleaseRankingDecision.create!(user:, release:, included: true)
    payload = { artist_name: artist.name, album_name: release.title, track_name: recording.title }
    recent_days = [ Time.current, 2.days.ago.utc.change(hour: 13) ] +
      ((1..12).to_a - [ 4, 8 ]).map { |days| days.days.ago.utc.change(hour: 12) }
    dates = [ Time.utc(2019, 12, 31), Time.utc(2020, 1, 2), 6.months.ago, 50.days.ago, *recent_days ]
    observations = dates.map { |played_at| Scrobble.create!(user:, lastfm_account: user.source_account, played_at:, payload:) }
    RecordingResolution::Ledger.record!(listener: user, scrobble: observations.first, scope: :surface,
      mode: "resolved", recording:, reason: "Fixture")
    sign_in(user)

    browser = page.driver.browser
    [ [ "Recording", recording, recordings_path ], [ "Release", release, releases_path ], [ "Artist", artist, artists_path ] ].each do |label, entity, index|
      visit index
      expect(page).to have_css(".library-nav a[aria-current='page'][href='#{index}']", exact_text: label.pluralize)
      visit polymorphic_path(entity)
      expect(page).to have_no_css(".library-nav [aria-current]")
      expect(page).to have_css(".entity-heading-label + h1")
      expect(page).to have_css(".entity-heading-label", exact_text: label.upcase)
      expect(page).to have_css(".catalog-heading + .entity-history")
      expect(page).to have_css("#entity-details:not([open])")
      expect(page).to have_no_button("Import")
      expect(page.evaluate_script("document.querySelector('.listening-plot').scrollWidth")).to be < 390
      expect(page).to have_text("42 min")
      if label == "Recording"
        expect(page).to have_css(".entity-history + section", text: /release appearances/i)
        expect(page).to have_css("#recording-chronology + #entity-details")
        expect(page).to have_text("Recording duration 2:38")
      end

      within("nav[aria-label='Listening history grouping']") { click_link "Months" }
      expect(page).to have_css(".artist-timeline-column[data-date='#{6.months.ago.to_date.beginning_of_month}']")
      expect(page).to have_css(".artist-timeline-column[data-date='2020-01-01'] time", exact_text: "2020")
      %w[Year 6m 90d 30d].each do |period|
        within("nav[aria-label='Listening history period']") { click_link period }
        expect(page).to have_css("nav[aria-label='Listening history period'] [aria-current]", exact_text: period)
        if %w[90d 30d].include?(period)
          expect(page).to have_no_css("nav[aria-label='Listening history grouping']")
        else
          expect(page).to have_css("nav[aria-label='Listening history grouping'] [aria-current]", exact_text: "Months")
        end
      end
      expect(page).to have_css(".artist-timeline-column[data-date='#{4.days.ago.utc.to_date}']:not(:has(.artist-timeline-fill))", visible: :all)
      expect(page).to have_css(".artist-timeline + .listening-summary", text: "(all time)")
      expect(page).to have_css(".artist-timeline-fill[title$='#{label == 'Recording' ? '1 play' : '3 min'}']", count: 10)
      expect(page).to have_css(".artist-timeline-fill[title$='#{label == 'Recording' ? '2 plays' : '5 min'}']", count: 1)
      find("#entity-details > summary").send_keys(:enter)
      expect(page).to have_css("#entity-details[open] .listening-periods li", count: 11)
      find("#entity-details > summary").send_keys(:space)
      expect(page).to have_css("#entity-details:not([open])")

      [ [ "desktop", 1440, 960, "light" ], [ "mobile", 390, 844, "dark" ] ].each do |size, width, height, theme|
        browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: size == "mobile")
        browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: theme } ])
        visit polymorphic_path(entity, range: "30d", grouping: "days")
        expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
        expect(page.evaluate_script(<<~JS)).to eq([ 10, 8, 2, true, true, true ])
          (() => {
            const mobile = #{size == "mobile"}
            const plot = document.querySelector(".listening-plot")
            const rects = [...plot.querySelectorAll(".artist-timeline-column")].map(slot => slot.getBoundingClientRect())
            const first = rects[0]
            const second = rects[1]
            const fills = [...plot.querySelectorAll(".artist-timeline-fill")].map(bar => bar.getBoundingClientRect())
            const sizes = fills.map(bar => mobile ? bar.width : bar.height)
            const heading = document.querySelector(".listening-history-heading h2").getBoundingClientRect()
            const controls = document.querySelector(".listening-controls").getBoundingClientRect()
            return [
              mobile ? first.top - second.top : second.left - first.left,
              mobile ? fills[0].height : fills[0].width,
              Math.max(...sizes) / Math.min(...sizes),
              mobile ? plot.scrollHeight > plot.clientHeight && plot.scrollWidth === plot.clientWidth
                : plot.scrollHeight === plot.clientHeight && rects.length * 10 < innerWidth / 2,
              mobile ? controls.top >= heading.bottom : controls.left >= heading.right && Math.abs(controls.top - heading.top) < 16,
              mobile ? rects.at(-1).top <= plot.getBoundingClientRect().top + 1
                : document.querySelector(".artist-timeline-bars").getBoundingClientRect().width === rects.length * 10
            ]
          })()
        JS
        capture_resolution("entity-#{label.downcase}-#{size}", full: true)
        %w[years months days].each do |grouping|
          visit polymorphic_path(entity, grouping:, range: grouping == "days" ? "year" : "all", start: grouping == "days" ? "2020-01-01" : nil)
          expect(page).to have_css(".artist-timeline-column:not(:has(.artist-timeline-fill))", minimum: 1, visible: :all)
          if grouping != "years"
            expect(page).to have_css(".artist-timeline-column[data-date='2020-01-01'] time", exact_text: "2020")
          end
          expect(page.evaluate_script(<<~JS)).to be(true)
            (() => {
              const mobile = #{size == "mobile"}
              const plot = document.querySelector(".listening-plot")
              const first = plot.querySelector(".artist-timeline-column").getBoundingClientRect()
              const last = plot.querySelector(".artist-timeline-column:last-child").getBoundingClientRect()
              const labels = [...plot.querySelectorAll(mobile ? ".listening-label-mobile" : ".listening-label-desktop")]
                .map(label => label.getBoundingClientRect()).sort((a, b) => mobile ? a.top - b.top : a.left - b.left)
              return (mobile ? last.top < first.top : last.left > first.left)
                && labels.every((label, i) => !i || (mobile ? labels[i - 1].bottom <= label.top : labels[i - 1].right <= label.left))
                && (#{grouping != "days"} || (mobile
                  ? plot.scrollHeight > plot.clientHeight
                  : plot.scrollWidth > plot.clientWidth))
            })()
          JS
        end
      end
    end
    expect(observations.map { |observation| observation.reload.payload }).to all(eq(payload.stringify_keys))
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
    browser&.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  it "orders catalog listening totals and clears filters without losing Archive colors" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "catalog-polish", lastfm_username: "catalog-polish")
    artist = Artist.create!(name: "Tove Lo", country: "SE", mbid: SecureRandom.uuid)
    Artist.create!(name: "A zero-play artist", mbid: SecureRandom.uuid)
    recording = Recording.create!(title: "hey you got drugs?", mbid: SecureRandom.uuid, duration_ms: 258_000)
    recording.artists << artist
    MusicalIdentityDecision.create!(entity: artist, user:, colors: %w[pink gray])
    release = Release.create!(title: "BLUE LIPS", release_year: 2017, catalog_verified_at: Time.current)
    release.artists << artist
    Release.create!(title: "A zero-play release")
    2.times do |position|
      release.catalog_track_slots.create!(recording:, title: recording.title, medium: 1, position: position + 1,
        track_mbid: SecureRandom.uuid)
    end
    ReleaseRankingDecision.create!(user:, release:, included: false)
    resolved = Scrobble.create!(user:, lastfm_account: user.source_account, played_at: 2.hours.ago,
      payload: { artist_name: artist.name, album_name: release.title, track_name: recording.title })
    pending = Scrobble.create!(user:, lastfm_account: user.source_account, played_at: 1.hour.ago,
      payload: { artist_name: artist.name, album_name: release.title, track_name: "bad days" })
    RecordingResolution::Ledger.record!(listener: user, scrobble: resolved, scope: :surface, mode: "resolved",
      reason: "Review fixture", recording:)
    sign_in(user)

    browser = page.driver.browser
    [ [ 1440, 960 ], [ 390, 844 ] ].product(%w[light dark]).each do |(width, height), theme|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width < 700)
      browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: theme } ])
      %w[artists releases recordings].each do |section|
        visit public_send("#{section}_path")
        expect(page).to have_no_link("Clear search")
        first, second = all(".catalog-table tbody tr")
        if section != "recordings"
          expect(first).to have_css(".listening-bar:not([data-identity-first])", text: "4 min")
          expect(second).to have_text("0 min")
          expect(page).to have_no_css(".intro h1")
        end
        capture_resolution("catalog-#{section}-#{width}-#{theme}") if section != "recordings"
        fill_in "Search #{section}", with: "zero-play"
        click_button "Search"
        expect(page).to have_link("Clear search")
        verify_clear_search_style
        if section == "recordings" && [ [ 1440, "light" ], [ 390, "dark" ] ].include?([ width, theme ])
          page.execute_script("document.activeElement.blur()") if theme == "light"
          capture_resolution("clear-search-#{width}-#{theme}")
        end
        find_link("Clear search").send_keys(:enter)
        expect(page).to have_no_link("Clear search")
        expect(page).to have_css(".catalog-table tbody tr", count: section == "recordings" ? 1 : 2)
      end

      visit archive_path(q: "bad days")
      expect(page).to have_css(".play-row", count: 1, text: pending.payload.fetch("track_name"))
      verify_clear_search_style
      capture_resolution("catalog-archive-search-#{width}-#{theme}")
      find_link("Clear search").send_keys(:enter)
      expect(page).to have_no_link("Clear search")
      expect(page).to have_css(".play-row", count: 2)
      expect(find(".play-row", text: "bad days")).to have_no_css(".play-badge .identity-swatch")
      expect(find(".play-row", text: recording.title)).to have_css('.play-length + .play-badge [data-identity-first="pink"][data-identity-second="gray"]')
      expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
      capture_resolution("catalog-archive-#{width}-#{theme}")

      visit artist_path(artist)
      find("#entity-details > summary").click
      expect(page).to have_css('.listening-periods .listening-bar[data-identity-first="pink"][data-identity-second="gray"]')
      capture_resolution("catalog-artist-listening-#{width}-#{theme}")

      visit resolution_surface_path(resolved)
      expect(page).to have_css(".review-state-resolved", exact_text: "Resolved")
      capture_resolution("catalog-resolved-#{width}-#{theme}")
      visit resolution_surface_path(pending)
      expect(page).to have_css(".review-state:not(.review-state-resolved)", exact_text: "Unresolved")
    end
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
    browser&.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  it "shows the approved overview and constructs Narrow Stairs from the original US CD" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "narrow-stairs-browser", lastfm_username: "narrow-stairs-browser")
    observation, assessment = narrow_stairs_assessment(user, album_name: "Narrow Stairs", publication: true)
    5.times do |index|
      Scrobble.create!(user:, lastfm_account: user.source_account, played_at: observation.played_at - (index + 1).hours,
        payload: observation.payload)
    end
    album_recording = assessment.evidence.fetch("candidates").sole
    compilation_recording = album_recording.except("releases").merge("id" => "5dffd281-d913-4256-8816-7035d077183f",
      "releases" => [ { "id" => "1cefec58-1706-4d52-bd93-bebaaa682e2d", "title" => "Time Warner 2", "date" => "2009" } ])
    RecordingResolution::Assessment.create!(group_id: assessment.group_id, version: assessment.version, actor: assessment.actor,
      digest: SecureRandom.hex(32), evidence: assessment.evidence.merge("candidates" => [
        compilation_recording.merge("length" => 160000), album_recording,
        compilation_recording.except("releases").merge("id" => "76c95b67-fcfd-4ba9-a579-56e65a9e1b4f", "length" => 168333),
        compilation_recording.except("releases").merge("id" => "ee10460e-f37b-4079-9aee-740477cfcc6e", "length" => 196284)
      ]))
    sign_in(user)
    visit resolution_surface_path(observation)

    within(".review-overview") do
      expect(page).to have_css("h1", text: "No Sunlight")
      expect(page).to have_text("Narrow Stairs")
      expect(page).to have_css(".review-catalog-context", text: /canonical in muzeum/i)
    end
    expect(page).to have_text("6 matching observations")
    expect(page).to have_css(".resolution-context", text: /Narrow Stairs.*May 13, 2008/m)
    expect(page).to have_css(".resolution-choice", count: 3)
    expect(page).to have_link("5dffd281", href: "https://musicbrainz.org/recording/5dffd281-d913-4256-8816-7035d077183f")
    expect(page).to have_link("e77221ef", href: "https://musicbrainz.org/recording/#{NarrowStairsFixture::RECORDING}")
    expect(page).to have_no_text("Original release pending")
    expect(find(".resolution-option", text: "2:48")).to have_no_css(".resolution-recording-mbid")
    expect(find(".resolution-choice[aria-current]")).to have_text("Narrow Stairs · 2008 · Track 3")
    find("summary", text: "More recording choices").click
    expect(page).to have_css(".resolution-choice", count: 4)
    expect(find(".resolution-option", text: "3:16")).to have_no_css(".resolution-recording-mbid")
    find("summary", text: "More recording choices").click
    expect(page).to have_css(".resolution-choice[aria-current]", count: 1)
    expect(page).to have_css(".resolution-primary", count: 1, text: "Resolve all 6")
    expect(page).to have_css('section[aria-label="Resolution preview"]', text: /Recording.*Release.*Narrow Stairs.*11 tracks.*1 new release.*6 existing observations/m)
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.resolution-primary')).backgroundColor")).to be_in([ "rgb(41, 45, 44)", "rgb(35, 38, 37)" ])
    expect(page).to have_css('.resolution-primary .resolution-confirmation-mark[aria-hidden="true"]')
    expect(page).to have_no_text("Provider calls")
    expect(page).to have_no_text("2015")
    expect(page).to have_css(".resolution-context .review-tracks li", count: 11)

    [ [ 1440, 960 ], [ 390, 844 ] ].each do |width, height|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width == 390)
      columns = page.evaluate_script("getComputedStyle(document.querySelector('.review-overview')).gridTemplateColumns").split
      expect(columns.size).to eq(width == 1440 ? 2 : 1)
      expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
      page.execute_script("window.scrollTo(0, 0)")
      %w[light dark].each do |mode|
        find(".shell-appearance > summary").send_keys(:enter)
        select mode.capitalize, from: "Appearance"
        find(".shell-appearance > summary").send_keys(:escape)
        expect(page).to have_css("html[data-appearance='#{mode}']", visible: :all)
        page.execute_script("window.scrollTo(0, 0)")
        capture_resolution("narrow-stairs-#{width}-#{mode}", full: true)
        primary = find(".resolution-primary")
        page.execute_script("arguments[0].scrollIntoView({ block: 'center' })", primary)
        capture_resolution("resolve-action-#{width}-#{mode}")
        verify_recording_choice_states(width, mode)
      end
    end

    expect(page).to have_css(".resolution-context .review-track-match", text: "No Sunlight")
    expect(page).to have_no_css(".resolution-context details")
    click_link "Review evidence"
    expect(page).to have_css(".review-score")
    expect(page).to have_css("details:not([open]) > summary", text: "Checked appearance · Narrow Stairs", visible: :all)
    click_link "Candidates"
    find_button("Resolve all 6").send_keys(:enter)
    expect(page).to have_text("Recording decision saved.")
    release = Release.find_by!(release_group_mbid: NarrowStairsFixture::GROUP)
    expect(release.ingested_from_release_mbid).to eq(NarrowStairsFixture::ORIGINAL)
    expect(release.catalog_track_slots.base_sequence.count).to eq(11)
    plays = RecordingResolution::Ledger.effective(user).where(lastfm_account_id: user.source_account.id).to_a
    expect(plays.size).to eq(6)
    expect(plays.map(&:effective_recording_id).uniq).to eq([ Recording.find_by!(mbid: NarrowStairsFixture::RECORDING).id ])
    expect(plays.map(&:payload).uniq).to eq([ observation.payload ])
  end

  it "shows the complete Charli sequence above a compact entity preview" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "charli-heading-browser", lastfm_username: "charli-heading-browser")
    observation = Scrobble.create!(user:, lastfm_account: user.source_account, played_at: Time.current,
      payload: { artist_name: "Charli XCX", album_name: "Charli", track_name: "Next Level Charli" })
    surface = RecordingResolution::Ledger.attach!(observation)
    group = RecordingResolution::Group.create!(surface_id: surface.id, version: RecordingResolution::Ledger::VERSION, claims: {})
    charli = { "artist" => { "id" => SecureRandom.uuid, "name" => "Charli xcx" }, "name" => "Charli XCX" }
    guest = { "artist" => { "id" => SecureRandom.uuid, "name" => "Troye Sivan" }, "name" => "Troye Sivan" }
    titles = [ "Next Level Charli", "Gone", "Cross You Out", "1999", "Click", "Warm", "Thoughts", "Blame It on Your Love",
      "White Mercedes", "Silver Cross", "I Don't Wanna Know", "Official", "Shake It", "February 2017", "2099" ]
    durations = [ 158, 246, 208, 189, 233, 225, 191, 191, 203, 208, 183, 184, 275, 152, 205 ]
    source_numbers = %w[A1 A2 A3 A4 B1 B2 B3 C1 C2 C3 C4 D1 D2 D3 D4]
    indexed_titles = titles.each_with_index.to_a
    media = [ indexed_titles.take(7), indexed_titles.drop(7) ].each.with_index(1).map do |entries, medium|
      tracks = entries.each.with_index(1).map do |(title, index), position|
        credits = index == 3 ? [ charli.merge("joinphrase" => " & "), guest ] : [ charli ]
        recording = { "id" => SecureRandom.uuid, "title" => title, "length" => durations.fetch(index) * 1000, "artist-credit" => credits }
        { "id" => SecureRandom.uuid, "title" => title, "position" => position, "number" => source_numbers.fetch(index),
          "recording" => recording }
      end
      { "position" => medium, "format" => '12" Vinyl', "track-count" => tracks.size, "tracks" => tracks }
    end
    edition = { "id" => SecureRandom.uuid, "title" => "Charli", "date" => "2019-09-13", "status" => "Official", "country" => "US",
      "release-group" => { "id" => SecureRandom.uuid, "title" => "Charli", "primary-type" => "Album", "first-release-date" => "2019-09-13" },
      "artist-credit" => [ charli ], "media" => media }
    first_recording = media.first.dig("tracks", 0, "recording")
    later_recording = media.last.dig("tracks", 0, "recording")
    alternative = first_recording.merge("id" => SecureRandom.uuid, "length" => 162_000)
    assessment = RecordingResolution::Assessment.create!(group_id: group.id, version: "charli-ui", actor: "fixture", digest: SecureRandom.hex(32),
      evidence: { "candidates" => [ first_recording, alternative ], "construction_editions" => [ edition ] })
    contexts = CanonicalCatalog::ReviewedConstruction.for(assessment, later_recording.fetch("id"))
    expect(ApplicationController.helpers.resolution_candidate_association(later_recording, contexts)).to eq("Charli · 2019 · Track 8")
    sign_in(user)

    browser = page.driver.browser
    [ [ 1440, 960 ], [ 390, 844 ] ].product(%w[light dark]).each do |(width, height), theme|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width < 700)
      browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: theme } ])
      visit resolution_surface_path(observation, candidate: first_recording["id"])
      expect(page).to have_css(".resolution-choice[aria-current]", text: "Charli · 2019 · Track 1")
      within(".resolution-context") do
        expect(page).to have_text("September 13, 2019")
        expect(page.evaluate_script(<<~JS)).to be(true)
          (() => {
            const section = document.querySelector(".resolution-context")
            const heading = getComputedStyle(section.querySelector("h2"))
            const title = getComputedStyle(section.querySelector("h3"))
            return heading.textTransform === "uppercase" && parseFloat(title.fontSize) > parseFloat(heading.fontSize)
          })()
        JS
        expect(page).to have_no_text(/Disc|Vinyl|Complete tracklist|MusicBrainz release/)
        expect(page).to have_no_css("details")
        expect(all(".review-tracks li > span:first-child").map(&:text)).to eq((1..15).map(&:to_s))
        expect(all(".review-tracks li > span:nth-child(2)").map { |element| element.text.sub(/\s+\(candidate recording\)\z/, "") }).to eq(titles)
      end
      within('[aria-label="Resolution preview"]') do
        expect(page).to have_text("Release · Charli · 15 tracks")
        find("summary", text: "2 credited artists").click
        expect(page).to have_text("Artist · Troye Sivan")
        expect(page).to have_no_text(/Create|2099/)
      end
      page.execute_script("scrollTo(0, 0)")
      capture_resolution("charli-#{width}-#{theme}", full: true)
    end

    click_button "Resolve this observation"
    expect(page).to have_text("Recording decision saved.")
    24.times do |index|
      Scrobble.create!(user:, lastfm_account: user.source_account, played_at: observation.played_at - (index + 1).minutes,
        payload: observation.payload)
    end
    artist = Artist.find_by!(name: "Charli xcx")
    release = Release.find_by!(title: "Charli")
    MusicalIdentityDecision.create!(entity: artist, user:, colors: %w[pink gray])
    colors = '[data-identity-first="pink"][data-identity-second="gray"]'

    [ [ 1440, 960 ], [ 390, 844 ] ].product(%w[light dark]).each do |(width, height), theme|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width < 700)
      browser.execute_cdp("Emulation.setEmulatedMedia", features: [
        { name: "prefers-color-scheme", value: theme }, { name: "prefers-reduced-motion", value: "reduce" }
      ])
      visit artist_path(artist)
      expect(page).to have_css("#artist-recordings .listening-bar#{colors}", text: "25")
      expect(page).to have_css("#artist-releases .listening-bar#{colors}")
      capture_resolution("charli-artist-bars-#{width}-#{theme}", full: true)

      visit release_path(release)
      expect(page).to have_css(".release-tracks tbody tr", count: 15)
      expect(all(".release-tracks .track-number", minimum: 16).drop(1).map(&:text)).to eq((1..15).map(&:to_s))
      expect(page).to have_css(".release-tracks .listening-bar#{colors}[data-listening-scale-percent-value='100.0']", text: "25", count: 1)
      expect(page).to have_css(".release-tracks td.track-play-count", exact_text: "0", count: 14)
      expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
      capture_resolution("charli-release-bars-#{width}-#{theme}")

      find(".catalog-heading .identity-badge").click
      expect(page).to have_css("dialog[open]", text: "Inherited from Charli xcx")
      expect(page).to have_css("#identity-color-pink:checked", visible: :all)
      expect(page).to have_css("#identity-color-gray:checked", visible: :all)
      expect(MusicalIdentityDecision.where(entity: release)).to be_empty
      capture_resolution("charli-guide-inherited-#{width}-#{theme}")
      find("label:has(#identity-color-pink)").click
      expect(page).to have_css("dialog[open]")
      expect(page).to have_no_css("#identity-color-pink:checked", visible: :all)
      page.driver.browser.action.send_keys(:escape).perform
      expect(page).to have_no_css("dialog[open]")
      expect(page).to have_css(".catalog-heading .identity-badge:focus")
    end

    find(".catalog-heading .identity-badge").click
    expect(page).to have_css("#identity-color-pink:checked", visible: :all)
    page.execute_script("document.getElementById('identity-color-blue').focus()")
    page.driver.browser.action.send_keys(:space).perform
    expect(page).to have_css("#identity-color-blue:checked:focus-visible", visible: :all)
    expect(page).to have_css("#guide-assignment textarea:required")
    fill_in "Musical rationale (required for three colors)", with: "Pop, electronic production, and soulful vocals"
    capture_resolution("charli-guide-three-colors")
    browser.execute_cdp("Input.dispatchMouseEvent", type: "mousePressed", x: 4, y: 200, button: "left", clickCount: 1)
    browser.execute_cdp("Input.dispatchMouseEvent", type: "mouseReleased", x: 4, y: 200, button: "left", clickCount: 1)
    expect(page).to have_no_css("dialog[open]")
    expect(page).to have_css(".catalog-heading .identity-badge:focus")
    expect(MusicalIdentityDecision.where(entity: release)).to be_empty

    find(".catalog-heading .identity-badge").click
    expect(page).to have_no_css("#identity-color-blue:checked", visible: :all)
    expect(find("#guide-assignment textarea").value).to eq("")
    find("label:has(#identity-color-blue)").click
    fill_in "Musical rationale (required for three colors)", with: "Pop, electronic production, and soulful vocals"
    click_button "Save colors"
    expect(page).to have_css("dialog[open]", text: "Direct assignment")
    expect(MusicalIdentityDecision.where(entity: release).last.colors).to eq(%w[pink gray blue])
    click_button "Use inherited colors"
    expect(page).to have_css("dialog[open]", text: "Inherited from Charli xcx")
    expect(MusicalIdentityDecision.where(entity: release).order(:id).pluck(:colors)).to eq([ %w[pink gray blue], [] ])

    click_button "Close"
    visit releases_path
    expect(page).to have_css(".listening-bar")
    expect(page).to have_no_css(".listening-bar[data-identity-first]")
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
    browser&.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  it "shows only the chosen release sequence and submits that one plan" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "competing-sequences", lastfm_username: "competing-sequences")
    observation, assessment = narrow_stairs_assessment(user)
    original = narrow_stairs_editions.find { |edition| edition["id"] == NarrowStairsFixture::ORIGINAL }
    other = original.deep_dup.merge("id" => SecureRandom.uuid)
    tracks = other.dig("media", 0, "tracks")
    tracks[0], tracks[1] = tracks[1], tracks[0]
    tracks.first(2).each_with_index { |track, index| track.merge!("position" => index + 1, "number" => (index + 1).to_s) }
    RecordingResolution::Assessment.create!(group_id: assessment.group_id, version: assessment.version, actor: assessment.actor,
      digest: SecureRandom.hex(32), evidence: assessment.evidence.merge("construction_editions" => [ original, other ]))
    sign_in(user)

    browser = page.driver.browser
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: "dark" } ])
    visit resolution_surface_path(observation)
    expect(page).to have_no_css(".resolution-context .review-tracks")
    choose "construct_release_#{original["id"]}"
    expect(page).to have_css(".resolution-context .review-tracks", count: 1)
    choose "construct_release_#{other["id"]}"
    expect(page).to have_css(".resolution-context .review-tracks", count: 1)
    expect(find(".resolution-context .review-tracks li", match: :first)).to have_text(tracks.first.fetch("title"))
    expect(page).to have_css('[aria-label="Resolution preview"] li', text: "1 new release", count: 1)
    capture_resolution("release-choice-mobile-dark", full: true)

    expect(page.evaluate_script("new FormData(document.querySelector('.resolution-confirmation')).get('construct_release')")).to eq(other["id"])
    find_button("Resolve this observation").send_keys(:enter)
    expect(page).to have_text("Recording decision saved.")
    expect(Release.sole.ingested_from_release_mbid).to eq(other["id"])
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
    browser&.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  it "confirms a Lady Wood source alias and the authentic original program in one resolution" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "lady-wood-browser", lastfm_username: "lady-wood-browser")
    provider = LadyWoodFixture::Session.new
    explicit, clean = %w[dd8c5328-1935-4ce0-a1ed-1df9e4f283cc d89399fb-fd54-4f36-8807-f679ac50a847]
    evidence = RecordingResolution::RecordingOrigins.new(Clients::Musicbrainz.new, provider).call([ explicit, clean ], retained: [])
    evidence["candidates"] = provider.fixture.fetch("recordings").values_at(explicit, clean)
    observation = Scrobble.create!(user:, lastfm_account: user.source_account, played_at: Time.current,
      payload: { artist_name: "Tove Lo", album_name: "Lady Wood", track_name: "Don’t Talk About It" })
    surface = RecordingResolution::Ledger.attach!(observation)
    group = RecordingResolution::Group.create!(surface_id: surface.id, version: RecordingResolution::Ledger::VERSION, claims: {})
    RecordingResolution::Assessment.create!(group_id: group.id, version: "retained-provider", actor: "fixture",
      digest: SecureRandom.hex(32), evidence:)
    sign_in(user)
    visit resolution_surface_path(observation, candidate: clean)
    expect(page).to have_css(".review-state", exact_text: "Unresolved")
    expect(page).to have_no_css(".investigation-badge", exact_text: "Needs review")
    expect(page).to have_css('[aria-label="Original release"] .resolution-release-title', text: "Lady Wood")
    expect(page).to have_css('[aria-label="Original release"] li', count: 12)
    expect(page).to have_css('[aria-label="Resolution preview"]', text: "1 equivalent source ID will be linked")
    page.execute_script("window.scrollTo(0, 0)")
    capture_resolution("lady-wood-identity-and-original", full: true)
    click_button "Resolve this observation"
    expect(page).to have_text("Recording decision saved.")
    decision = RecordingResolution::Decision.sole
    canonical = Recording.find(decision.recording_id)
    expect(canonical.mbid).to eq(explicit)
    expect(decision.evidence.fetch("source_recording_mbid")).to eq(clean)
    expect(RecordingSourceDecision.resolve(clean)).to eq(canonical)
    expect(Release.sole.catalog_track_slots.base_sequence.count).to eq(12)
    expect(Scrobble.count).to eq(1)
  end

  it "keeps the reported Blur title visible alongside the interpreted search and catalog evidence" do
    album = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/discovery/blur-leisure-us.json").read)
    slot = album.dig("media", 0, "tracks", 11)
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "structured-titles", lastfm_username: "structured-titles")
    payload = { artist_name: "Blur", album_name: "Leisure", track_name: "Wear Me Down - 2012 Remaster" }
    play = Scrobble.create!(user:, lastfm_account: user.source_account, played_at: Time.current, payload:)
    surface = RecordingResolution::Ledger.attach!(play)
    group = RecordingResolution::Group.create!(surface_id: surface.id, version: RecordingResolution::Ledger::VERSION, claims: {})
    recording = slot.fetch("recording")
    RecordingResolution::Assessment.create!(group_id: group.id, version: "structured-title-fixture", actor: "fixture",
      digest: SecureRandom.hex(32), evidence: {
        "title_interpretation" => RecordingResolution::TitleInterpretation.call(surface.track),
        "candidates" => [ recording ], "construction_editions" => [ album ],
        "recording_publications" => { recording.fetch("id") => { "original_groups" => [ album.dig("release-group", "id") ] } }
      })

    sign_in(user)
    visit resolution_surface_path(play)
    expect(page).to have_css("h1", exact_text: payload.fetch(:track_name))
    find("summary", exact_text: "Wear Me Down — 2012 remaster").click
    expect(page).to have_text("Search interpretation from the reported title.")
    expect(page).to have_css(".resolution-choices", text: "Wear Me Down")
    capture_resolution("wear-me-down-interpretation-desktop", full: true)
    page.driver.browser.manage.window.resize_to(390, 844)
    capture_resolution("wear-me-down-interpretation-mobile", full: true)
    expect(play.reload.payload.fetch("track_name")).to eq(payload.fetch(:track_name))
    expect(RecordingResolution::Decision.count).to eq(0)
  end

  it "shows the selected Blur album once and confines a verified mispressing to recording provenance" do
    editions = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/discovery/blur-checked-editions.json").read)
    album = editions.find { |edition| edition["id"] == "dc2c22eb-9e48-4caa-8263-87c4cfe40a1a" }
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "blur-provenance", lastfm_username: "blur-provenance")
    groups = editions.map { |edition| edition.dig("release-group", "id") }.uniq
    [ [ 12, "Wear Me Down - 2012 Remaster" ], [ 1, "She's so High – 2012 Remaster" ] ].each do |position, title|
      payload = { artist_name: "Blur", album_name: "Leisure", track_name: title }
      play = Scrobble.create!(user:, lastfm_account: user.source_account, played_at: Time.current, payload:)
      surface = RecordingResolution::Ledger.attach!(play)
      group = RecordingResolution::Group.create!(surface_id: surface.id, version: RecordingResolution::Ledger::VERSION, claims: {})
      recording = album.dig("media", 0, "tracks", position - 1, "recording")
      RecordingResolution::Assessment.create!(group_id: group.id, version: "blur-provenance-fixture", actor: "fixture",
        digest: SecureRandom.hex(32), evidence: {
          "title_interpretation" => RecordingResolution::TitleInterpretation.call(surface.track),
          "candidates" => [ recording ], "construction_editions" => editions,
          "recording_publications" => { recording.fetch("id") => { "original_groups" => groups } }
        })

      sign_in(user) if position == 12
      visit resolution_surface_path(play)
      expect(page).to have_css("h1", exact_text: title)
      expect(page).to have_no_css('[aria-label="Original release"]')
      find(".recording-choice-form input[type=checkbox]").click
      expect(page).to have_css("#recording-resolution-confirmation button", text: /Resolve/)
      find("summary", text: "Release configurations and adjacent programs").click
      within('[aria-label="Verified album configurations"]') do
        expect(page).to have_css("summary", text: "Disputed source", count: 1)
        expect(page).to have_no_text("Modern Life Is Rubbish")
      end
      expect(page).to have_css("#recording-resolution-confirmation button", text: /Resolve/)
      if position == 12
        disclosure = find("summary", exact_text: "Other verified appearances of this recording")
        expect(disclosure.find(:xpath, "..")).to match_css("details:not([open])")
        disclosure.click
        expect(page).to have_css('a[href="https://musicbrainz.org/release/12625b09-8ea4-46d8-b4e3-b916e819e039"]', text: /Modern Life Is Rubbish.*mispressing/)
        expect(page).to have_text("Medium 1, track 14")
        capture_resolution("wear-me-down-desktop", full: true)
      else
        page.driver.browser.manage.window.resize_to(390, 844)
        capture_resolution("shes-so-high-mobile", full: true)
      end
      expect(play.reload.payload.fetch("track_name")).to eq(title)
    end
    expect(RecordingResolution::Decision.count).to eq(0)
  end

  it "keeps independent ordered Charli artist lists in review, catalog pages, and credited-artist searches" do
    editions = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/construction/charli_featured_credit.json").read)
    album = editions.first
    source = album.dig("media", 0, "tracks", 2, "recording")
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "ordered-credits", lastfm_username: "ordered-credits")
    payload = { artist_name: "Charli xcx", album_name: "Charli", track_name: "Cross You Out (feat. Sky Ferreira)" }
    play = Scrobble.create!(user:, lastfm_account: user.source_account, played_at: Time.current, payload:)
    surface = RecordingResolution::Ledger.attach!(play)
    group = RecordingResolution::Group.create!(surface_id: surface.id, version: RecordingResolution::Ledger::VERSION, claims: {})
    release_group = album.dig("release-group", "id")
    full_title = %(artist:"Charli xcx" AND recording:"#{payload.fetch(:track_name)}")
    featured_title = 'artist:"Charli xcx" AND recording:"Cross You Out" AND artist:"Sky Ferreira"'
    legacy = RecordingResolution::Assessment.create!(group_id: group.id, version: "legacy-search-fixture", actor: "fixture",
      digest: SecureRandom.hex(32), evidence: {
        "candidates" => [], "search" => { "count" => 0, "returned" => 0 },
        "requests" => [ { "provider" => "musicbrainz", "endpoint" => "/ws/2/recording", "parameters" => { "query" => full_title } } ]
      })
    sign_in(user)
    visit resolution_surface_path(play, section: "evidence", assessment: legacy.id)
    find("summary", exact_text: "Assessment evidence and provenance").click
    expect(page).to have_text("MusicBrainz returned 0 candidates of 0.")
    find("summary", exact_text: "MusicBrainz recording searches").click
    expect(page).to have_css("code", exact_text: full_title)

    RecordingResolution::Assessment.create!(group_id: group.id, version: "featured-credit-fixture", actor: "fixture",
      digest: SecureRandom.hex(32), evidence: {
        "candidates" => [ source ], "construction_editions" => editions,
        "recording_searches" => [ { "query" => full_title, "count" => 0, "returned" => 0 },
          { "query" => featured_title, "count" => 1, "returned" => 1 } ],
        "recording_publications" => { source.fetch("id") => { "original_groups" => [ release_group ] } }
      })

    visit resolution_surface_path(play, section: "evidence")
    find("summary", exact_text: "Assessment evidence and provenance").click
    find("summary", exact_text: "MusicBrainz recording searches").click
    expect(page).to have_css("code", exact_text: featured_title)
    expect(page).to have_text("1 result returned")
    visit resolution_surface_path(play)
    within(".resolution-choices") { expect(page).to have_text("Charli xcx, Sky Ferreira") }
    within('[aria-label="Resolution preview"]') do
      expect(page).to have_text("Recording · Cross You Out · Charli xcx, Sky Ferreira")
      expect(page).to have_text("Release · Charli · 15 tracks")
    end
    capture_resolution("featured-credit-resolution", full: true)
    click_button "Resolve this observation"
    expect(page).to have_text("Recording decision saved.")

    entry = Recording.find_by!(mbid: source.fetch("id"))
    release = Release.sole
    expect(entry.recording_artists.includes(:artist).map { |row| [ row.position, row.artist.name ] })
      .to eq([ [ 1, "Charli xcx" ], [ 2, "Sky Ferreira" ] ])
    expect(release.release_artists.includes(:artist).map { |row| [ row.position, row.artist.name ] }).to eq([ [ 1, "Charli xcx" ] ])
    expect(Artist.where(name: [ "Charli xcx", "Sky Ferreira" ]).count).to eq(2)
    expect(Artist.find_by!(name: "Sky Ferreira").recordings).to include(entry)
    expect(play.reload.payload.slice(*payload.keys.map(&:to_s))).to eq(payload.stringify_keys)
    expect(Scrobble.count).to eq(1)

    visit recording_path(entry)
    expect(page).to have_css(".catalog-credit", exact_text: "Charli xcx, Sky Ferreira")
    capture_resolution("ordered-recording-credits")
    visit release_path(release)
    expect(page).to have_css(".catalog-credit", exact_text: "Charli xcx")

    visit recordings_path(q: "Sky Ferreira")
    expect(page).to have_link("Cross You Out")
    expect(page).to have_text("Charli xcx, Sky Ferreira")
    visit releases_path(q: "Sky Ferreira")
    expect(page).to have_no_link("Charli", exact: true)
  end

  it "compares the authentic Queen of the Clouds editions and recalculates additions from the chosen base" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "queen-comparison", lastfm_username: "queen-comparison")
    editions = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/construction/queen_of_the_clouds.json").read)
    fixtures = Rails.root.join("spec/fixtures/musicbrainz/construction")
    editions.concat(JSON.parse(fixtures.join("queen_of_the_clouds_launch_extensions.json").read))
    editions << JSON.parse(fixtures.join("queen_of_the_clouds_vinyl.json").read)
    canadian, overseas, worldwide = %w[
      9cd3b250-dc88-450f-8836-dbd0e0fa2ccc 17e2d704-6ee3-45ad-a494-d92b1d13abcc 1f21b9a1-0b81-4f3b-8b1b-3ff9e44a91ae
    ]
    original = editions.find { |edition| edition["id"] == canadian }
    recording = original.dig("media", 0, "tracks").map { |track| track.fetch("recording") }
      .find { |item| item["id"] == "461e6686-2af9-4def-82b0-411ada1a73ed" }
    observation = Scrobble.create!(user:, lastfm_account: user.source_account, played_at: Time.current,
      payload: { artist_name: "Tove Lo", album_name: "Queen of the Clouds", track_name: "Not on Drugs" })
    surface = RecordingResolution::Ledger.attach!(observation)
    group = RecordingResolution::Group.create!(surface_id: surface.id, version: RecordingResolution::Ledger::VERSION, claims: {})
    save_evidence = ->(sources) do
      RecordingResolution::Assessment.create!(group_id: group.id, version: "construction-fixture", actor: "fixture",
        digest: SecureRandom.hex(32), evidence: { "candidates" => [ recording ], "construction_editions" => sources })
    end
    save_evidence.call(editions)
    sign_in(user)
    browser = page.driver.browser
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: "light" } ])
    visit resolution_surface_path(observation)

    expect(page).to have_css(".resolution-option:has([aria-current]) .resolution-option-status .investigation-badge", exact_text: "Needs review")
    [ [ 1280, 800 ], [ 390, 844 ] ].each do |width, height|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width < 700)
      position = page.evaluate_script(<<~JS)
        (() => {
          const row = document.querySelector(".resolution-option:has([aria-current])")
          const label = row.querySelector(".resolution-selected").getBoundingClientRect()
          const badge = row.querySelector(".investigation-badge").getBoundingClientRect()
          const heading = document.querySelector("#review-candidates h2").getBoundingClientRect()
          return [Math.abs(label.top + label.height / 2 - badge.top - badge.height / 2),
            badge.left >= label.right || badge.top >= label.bottom,
            heading.bottom <= row.getBoundingClientRect().top,
            badge.right <= row.getBoundingClientRect().right]
        })()
      JS
      expect(position.drop(1)).to eq([ true, true, true ])
      expect(position.first).to be < 1 if width >= 700
    end
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 1280, height: 800, deviceScaleFactor: 1, mobile: false)

    within(".release-comparison") do
      expect(page).to have_css(".release-edition-group", count: 2)
      [ canadian, overseas, worldwide ].each do |id|
        expect(page).to have_css("a[href='https://musicbrainz.org/release/#{id}']", text: id.first(8))
      end
      find("summary", text: "15 shared opening tracks").click
      expect(page).to have_css("details[open] li", count: 15)
      find("summary", text: "15 shared opening tracks").click
      expect(page).to have_css('tr[data-change="Shared recording"] td', text: /1[67].*Hippie Sabotage/i, count: 2)
    end

    choose "construct_release_#{canadian}"
    preview = '[aria-label="Resolution preview"]'
    find("#{preview} summary", text: "7 additional edition tracks").click
    [ "Love Ballad", "Over", "Out Of Mind - Bonus Track", "Paradise" ].each do |title|
      expect(page).to have_css("#{preview} details li", text: /\A#{Regexp.escape(title)} · Edition evidence\z/, count: 1)
    end
    page.execute_script("window.scrollTo(0, 0)")
    capture_resolution("queen-release-comparison-desktop", full: true)

    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: "dark" } ])
    choose "construct_release_#{worldwide}"
    expect(page).to have_css("#{preview} summary", text: "3 additional edition tracks")
    within(preview) do
      find("summary", text: "3 additional edition tracks").click
      within("details", text: "3 additional edition tracks") do
        expect(page).to have_no_css("li", text: /Hippie Sabotage/i)
      end
      find("summary", text: "Edition tracks with unverified recording identity").click
      expect(page).to have_link("Queen of the Clouds", href: "https://musicbrainz.org/release/188f6468-b19e-4088-a6d3-0411f52692e4")
    end
    expect(page).to have_css("#{preview} li", text: /20 tracks.*1 new release/)
    page.execute_script("window.scrollTo(0, 0)")
    capture_resolution("queen-release-comparison-mobile-dark", full: true)
    request = CatalogImport.request!(RecordingResolution::Investigation::KIND, group.id)
    visit page.current_url
    expect(page).to have_css("turbo-cable-stream-source[connected]", visible: :all)
    refreshed = save_evidence.call(editions)
    Turbo::StreamsChannel.broadcast_refresh_to(request, method: :morph, scroll: :preserve)
    expect(page).to have_css("input[name='assessment_id'][value='#{refreshed.id}']", visible: :all)
    expect(page).to have_checked_field("construct_release_#{worldwide}")

    changed = save_evidence.call(editions.reject { |edition| edition["id"] == worldwide })
    Turbo::StreamsChannel.broadcast_refresh_to(request, method: :morph, scroll: :preserve)
    expect(page).to have_css("input[name='assessment_id'][value='#{changed.id}']", visible: :all)
    expect(page).to have_css("[role='alert']", text: "The selected edition is no longer in this review")
    expect(page).to have_no_css(".release-edition-choices input:checked")

    restored = save_evidence.call(editions)
    Turbo::StreamsChannel.broadcast_refresh_to(request, method: :morph, scroll: :preserve)
    expect(page).to have_css("input[name='assessment_id'][value='#{restored.id}']", visible: :all)
    expect(page).to have_no_css(".release-edition-choices input:checked")
    choose "construct_release_#{overseas}"

    click_button "Resolve this observation"
    expect(page).to have_text("Recording decision saved.")
    release = Release.sole
    expect(release.ingested_from_release_mbid).to eq(overseas)
    selected = CanonicalCatalog::Edition.new(editions.find { |edition| edition["id"] == overseas }, overseas)
    expect(release.catalog_track_slots.base_sequence.order(:medium, :position).pluck(:source_recording_mbid))
      .to eq(selected.slots.pluck(:source_recording_mbid))
    source_signature = selected.slots.map { |slot| slot.values_at(:medium, :position, :source_recording_mbid) }
    expect(RecordingResolution::ReleaseTracklist.new(release).evidence.fetch("tracklist_digest"))
      .to eq(Digest::SHA256.hexdigest(source_signature.to_json))
    visit release_path(release)
    find("summary", text: /Alternative edition evidence.*7 recordings/).click
    expect(page).to have_no_css(".additional-track-table")
    expect(release.catalog_track_slots.additional_appearances).to be_empty
    click_link "Love Ballad"
    first(:button, "Admit additional recording").click
    expect(page).to have_text("Additional recording admitted.")
    expect(ReleaseTrackListeningDecision.count).to eq(0)
    expect(release.catalog_track_slots.additional_appearances.count).to eq(1)
    find('input[aria-label="Count Love Ballad in release listening totals"]').send_keys(:space)
    expect(page).to have_css('input[aria-label="Count Love Ballad in release listening totals"]:checked')
    expect(ReleaseTrackListeningDecision.sole).to have_attributes(user:, release:, included: true)
    expect(Release.count).to eq(1)
    preference = ReleaseTrackListeningDecision.sole
    love_ballad = preference.recording
    choices = CanonicalCatalog::ReviewedConstruction.for(restored, recording.fetch("id"))
    [ [ worldwide, 20, false ], [ canadian, 16, true ] ].each do |edition, size, has_checkbox|
      proposal = choices.find { |item| item.construction.base.data.fetch("id") == edition }
      release.with_lock do
        review = CatalogImport.create!(kind: "release_construction", state: "imported", entity_id: release.id, due_at: Time.current)
        CanonicalCatalog::ReviewedConstruction.apply!(proposal, review, restored, corrected_release: release)
      end
      expect(release.catalog_track_slots.base_sequence.count).to eq(size)
      expect(release.catalog_track_slots.where(source_recording_mbid: "21c565a5-fbbd-4cd3-be5d-b921e534c014")).not_to exist
      counted = ReleaseTrackListeningDecision.included_memberships(user, [ release.id ]).pluck(:recording_id)
      plays = RecordingResolution::Ledger.for_recordings(user, counted)
      expect(CatalogListening.new(plays).total.plays).to eq(1)
      expect(ReleaseTrackListeningDecision.included_memberships(user, [ release.id ]).where(recording: love_ballad)).to exist
      visit release_path(release, edition_tracks: "1")
      checkbox = 'input[aria-label="Count Love Ballad in release listening totals"]:checked'
      expect(page).to(has_checkbox ? have_css(checkbox) : have_no_css(checkbox))
    end
    expect(ReleaseTrackListeningDecision.sole).to eq(preference)
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
    browser&.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  it "constructs Guilt Show and keeps the later appearance outside the original sequence" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "construction-browser", lastfm_username: "guilt-show-browser")
    plays, = guilt_show_assessment(user)
    sign_in(user)
    visit resolution_surface_path(plays.first)
    expect(page).to have_button("Resolve all 3")
    click_link "Review evidence"
    find("summary", text: "Review release construction").click
    expect(page).to have_text("Like a Man Possessed · 2004-08-21")
    verify_appearances("resolution-guilt-show")
    click_link "Candidates"
    click_button "Resolve all 3"
    expect(page).to have_text("Recording decision saved.")
    within(".review-catalog-context") { click_link "Guilt Show" }
    expect(page).to have_css("details.additional-edition-tracks:not([open])", text: "Additional edition tracks")
    within(".additional-edition-tracks") { expect(page).to have_no_link("Like a Man Possessed") }
    find("summary", text: "Additional edition tracks").send_keys(:enter)
    within(".additional-track-table tbody tr") do
      expect(page).to have_link("Like a Man Possessed")
      edition = guilt_show_editions.second.fetch("id")
      expect(page).to have_css("a[href='https://musicbrainz.org/release/#{edition}']", exact_text: edition.first(8))
      expect(page).to have_text("Guilt Show")
      expect(page).to have_text("4:08")
      expect(page).to have_css("td:last-child", exact_text: "3")
    end
    browser = page.driver.browser
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 1280, height: 800, deviceScaleFactor: 1, mobile: false)
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: "light" } ])
    [ [ 1280, 800 ], [ 390, 844 ] ].product(%w[light dark]).each do |(width, height), theme|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width < 700)
      browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: theme } ])
      geometry = page.evaluate_script(<<~JS)
        (() => {
          const baseRows = document.querySelectorAll(".release-tracks:not(.additional-track-table) tbody tr")
          const baseHeight = Math.min(...Array.from(baseRows, row => row.getBoundingClientRect().height))
          const row = document.querySelector(".additional-track-table tbody tr")
          const rect = row.getBoundingClientRect()
          const checkbox = row.cells[0].querySelector("input[type=checkbox]").getBoundingClientRect()
          return [Math.abs((checkbox.top + checkbox.height / 2) - (rect.top + rect.height / 2)), baseHeight, rect.height,
            Array.from(row.cells).map(cell => getComputedStyle(cell).whiteSpace)]
        })()
      JS
      expect(geometry[0]).to be < 1
      expect((geometry[1] - geometry[2]).abs).to be < 2
      expect(geometry[3]).to eq(Array.new(6, "nowrap"))
    end
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 1280, height: 800, deviceScaleFactor: 1, mobile: false)
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: "light" } ])
    page.execute_script("window.scrollTo(0, 0)")
    capture_resolution("guilt-show-additional-tracks", full: true)
    expect(page).to have_text("0 distinct resolved observations")
    checkbox = 'input[aria-label="Count Like a Man Possessed in release listening totals"]'
    expect(page).to have_css(".additional-edition-tracks input[type=checkbox]", count: 1)
    expect(page).to have_css("#{checkbox}:not(:checked)")
    find(checkbox).send_keys(:space)
    expect(page).to have_text("3 distinct resolved observations")
    expect(page).to have_text("12 min estimated listening time")
    release_url = page.current_url
    artist = Release.sole.artists.find_by!(name: "The Get Up Kids")
    visit artist_path(artist)
    within("#artist-releases") do
      expect(page).to have_link("Guilt Show")
      expect(page).to have_text("3 plays")
      expect(page).to have_text("12 min")
    end
    visit release_url
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: "dark" } ])
    visit page.current_url
    expect(page).to have_css("#{checkbox}:checked")
    page.execute_script("window.scrollTo(0, 0)")
    expect(page.evaluate_script(<<~JS)).to be(true)
      (() => {
        const row = document.querySelector(".additional-track-table tbody tr")
        const scroller = row.closest(".table-scroll")
        scroller.scrollLeft = scroller.scrollWidth
        const visible = scroller.scrollLeft > 0 && row.lastElementChild.textContent.trim() === "3"
        scroller.scrollLeft = 0
        return visible && document.documentElement.scrollWidth <= innerWidth
      })()
    JS
    capture_resolution("guilt-show-track-preferences", full: true)
    browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    find(checkbox).send_keys(:space)
    expect(page).to have_text("0 distinct resolved observations")
    expect(ReleaseTrackListeningDecision.order(:id).pluck(:included)).to eq([ true, false ])
    expect(Release.sole.catalog_track_slots.base_sequence.count).to eq(13)
    visit artist_path(artist)
    within("#artist-releases") { expect(page).to have_text("0 plays") }
  end

  it "reviews a candidate, applies it using the keyboard, and opens the admitted track listing" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "canonical-browser", lastfm_username: "canonical-browser")
    observation = catalog_observation(user, time: Time.utc(2024, 8, 20, 20, 15))
    catalog_assessment(observation)
    sign_in(user)
    visit releases_path
    expect(page).to have_text("No canonical releases yet")
    visit resolution_surfaces_path(filter: "unresolved")
    expect(page).to have_text("Candidate found")
    capture_resolution("unresolved-queue-desktop")
    browser = page.driver.browser
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
    capture_resolution("unresolved-queue-mobile")
    browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    click_link "Review candidate evidence"
    expect(page).to have_current_path(resolution_surface_path(observation))
    find_button("Resolve recording only").send_keys(:enter)
    expect(page).to have_text("Recording decision saved.")

    request = CatalogImport.find_by!(kind: CatalogImport::RECORDING_METADATA)
    expect(request.state).to eq("pending")
    expect(page).to have_css("turbo-cable-stream-source[connected]", visible: :all)
    expect(page).to have_css(".review-catalog-context", text: "Checking recording metadata")
    session = CatalogFixtures::Session.new
    allow(RecordingResolution::ProviderSession).to receive(:new).and_return(session)
    CanonicalCatalogJob.perform_now(request.id)
    expect(request.reload.state).to eq("imported")
    expect(Release.count).to eq(0)
    expect(page).to have_css(".review-catalog-context", text: "Release verification pending")
    explicit = CatalogImport.request!("recording", request.entity_id)
    CanonicalCatalogJob.perform_now(explicit.id)
    expect(page).to have_css(".review-catalog-context dl > div:last-child .review-catalog-mark.present")
    expect(page).to have_link("Night Drive", href: release_path(Release.find_by!(title: "Night Drive")))
    release = Release.find_by!(title: "Night Drive")
    visit resolution_surface_path(observation)
    click_button "Resolve this observation"
    expect(page).to have_text("Recording decision saved.")
    second_import = CatalogImport.latest(CatalogImport::RECORDING_METADATA, request.entity_id)
    expect(second_import.id).not_to eq(request.id)
    CanonicalCatalogJob.perform_now(second_import.id)
    expect(second_import.reload.state).to eq("imported")
    expect(Release.where(title: "Night Drive").pluck(:id)).to eq([ release.id ])
    expect(page).to have_css(".review-catalog-context a[href='#{release_path(release)}']")

    visit releases_path
    click_link "Night Drive"
    expect(page).to have_current_path(release_path(release))
    expect(page).to have_text(/track listing/i)
    within("#listening-activity") do
      expect(page).to have_text("1 distinct resolved observation")
    end
    expect(all("tbody tr").length).to eq(3)
    expect(all(".track-number", minimum: 4).map(&:text)).to eq([ "#", "1", "2", "3" ])
    verify_appearances("release")
    find("#entity-details > summary").send_keys(:enter)
    within("#entity-details") { expect(page).to have_link("Signals") }
    find_link("Different Song").hover
    expect(inverted_link?).to be(true)
    capture_link_state("hover")
    page.execute_script("document.querySelector('h1').scrollIntoView()")
    find(".library-nav a", text: "Archive").hover
    page.execute_script("document.querySelector('.catalog-table a').focus()")
    expect(inverted_link?).to be(true)
    capture_link_state("focus")

    click_link "Different Song"
    expect(page).to have_current_path(recording_path(Recording.find_by!(title: "Different Song")))
    expect(page).to have_text("0 resolved listening observations")
    expect(page).to have_link("Night Drive")
    find("#entity-details > summary").send_keys(:enter)
    click_button "Import"
    expect(page).to have_text("Pending enrichment")
    visit artists_path
    click_link "Night Lines"
    expect(page).to have_current_path(artist_path(Artist.find_by!(name: "Night Lines")))
    expect(page).to have_link("Different Song")
    expect(page).to have_link("Night Drive")
    expect(page).to have_css("#listening-history", text: "3 min estimated listening time")
    expect(page).to have_css(".artist-timeline-fill[data-listening-scale-percent-value='100.0']")
    find("#listening-history a", text: "30d").click
    expect(page).to have_text("No resolved plays in this period.")
    find("#listening-history a", text: "All").click
    expect(page).to have_css("#listening-history [aria-current]", exact_text: "All")
    expect(page).to have_css("#artist-recordings tbody tr:first-child .listening-bar[data-listening-scale-percent-value='100.0']", text: "1")
    find("#artist-recordings a", exact_text: "Title").send_keys(:enter)
    expect(page).to have_css("#artist-recordings th[aria-sort='ascending']", text: "Title")
    expect(page).to have_css("#artist-recordings tbody tr:first-child", text: "Different Song")
    expect(page).to have_css("#artist-releases .listening-bar", text: "3 min")
    expect(page).to have_css("#artist-releases", text: "1 play")
    visit artist_path(Artist.find_by!(name: "Night Lines"))
    verify_appearances("artist")
    artist = Artist.find_by!(name: "Night Lines")
    MusicalIdentityDecision.create!(entity: Recording.find(request.entity_id), user:, colors: %w[pink])
    visit artist_path(artist)
    find(".intro .identity-badge").click
    within("#guide-assignment") do
      find("label:has(#identity-color-light-green)").click
      find("label:has(#identity-color-blue)").click
      fill_in "Musical rationale (required for three colors)", with: "Harmonic vocabulary and funk groove"
      capture_resolution("identity-correction")
      click_button "Save colors"
    end
    expect(page).to have_css("dialog[open]", text: "Musical identity saved.")
    click_button "Close"
    expect(page).to have_css('.identity-chart[data-identity-first="light-green"][data-identity-second="blue"]')
    expect(page).to have_css('#artist-recordings .identity-badge[data-identity-first="pink"]')
    expect(page).to have_css('#artist-recordings .listening-bar[data-identity-first="light-green"]')
    verify_appearances("artist-colors")

    visit resolution_surface_path(observation, play: observation.id, section: "evidence")
    expect(page).to have_button("Resolve 1 observation")
    expect(page).to have_text("Resolve only this observation")
    expect(page).to have_text("Inherited from your exact-surface assignment")
    verify_appearances("resolution")
  end

  it "shows real Solid Queue transitions and catches up after a missed worker outcome" do
    ActiveRecord::Migration.suppress_messages { load Rails.root.join("db/queue_schema.rb") }
    prior_adapter = CanonicalCatalogJob.queue_adapter
    CanonicalCatalogJob.queue_adapter = :solid_queue
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "live-investigation", lastfm_username: "live-investigation")
    observation = catalog_observation(user)
    sign_in(user)
    browser = page.driver.browser
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 1280, height: 800, deviceScaleFactor: 1, mobile: false)
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: "light" } ])
    visit resolution_surface_path(observation)
    state = ".investigation-progress li[aria-current='true']"
    stream = "[data-controller='investigation-sync'] turbo-cable-stream-source"
    expect(page).to have_css(state, exact_text: "Queued")
    expect(page).to have_css(".investigation-progress li", count: 5)
    expect(page).to have_css("#{stream}[connected]", visible: :all)
    expect(page).to have_text("Eligible worker unavailable")
    expect(page).to have_text("A reliable position is unavailable")
    [ [ 1280, 800 ], [ 390, 844 ] ].product(%w[light dark]).each do |(width, height), theme|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width < 700)
      browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: theme } ])
      verify_investigation_state_colors("queued")
    end
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 1280, height: 800, deviceScaleFactor: 1, mobile: false)
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: "light" } ])

    request = CatalogImport.where(kind: RecordingResolution::Investigation::KIND).sole
    queued = SolidQueue::ReadyExecution.sole
    worker = SolidQueue::Process.create!(kind: "Worker", name: "queue-test", pid: 1, hostname: "test",
      created_at: 12.minutes.ago, last_heartbeat_at: Time.current, metadata: { queues: "default,canonical_catalog", pool_size: 1 })
    higher = CanonicalCatalogJob.new(0).serialize.merge("queue_name" => "default")
    job = SolidQueue::Job.create!(queue_name: "default", class_name: CanonicalCatalogJob.name, arguments: higher, priority: 0)
    Turbo::StreamsChannel.broadcast_refresh_to(request, method: :morph, scroll: :preserve)
    expect(page).to have_text("1 ready job ahead at last check")
    capture_resolution("investigation-queued", full: true)

    job.ready_execution.destroy!
    SolidQueue::ClaimedExecution.create!(job:, process_id: worker.id)
    queued.update!(created_at: 10.minutes.ago)
    Turbo::StreamsChannel.broadcast_refresh_to(request, method: :morph, scroll: :preserve)
    expect(page).to have_text("Eligible workers are busy")
    expect(page).to have_text("Time waiting 10:")
    expect(page).to have_css(state, exact_text: "Queued")

    job.destroy!
    expect(page).to have_text("The queue appears stalled", wait: 20)
    expect(page).to have_no_css(".investigation-progress")
    worker.update!(last_heartbeat_at: 30.minutes.ago)
    Turbo::StreamsChannel.broadcast_refresh_to(request, method: :morph, scroll: :preserve)
    expect(page).to have_text("No eligible worker has a current heartbeat")
    expect(page).to have_no_css(".investigation-progress")

    waiting_job = queued.job
    queued.destroy!
    waiting_job.update!(concurrency_key: "queue-test")
    SolidQueue::BlockedExecution.create!(job: waiting_job)
    Turbo::StreamsChannel.broadcast_refresh_to(request, method: :morph, scroll: :preserve)
    expect(page).to have_text("Blocked by a concurrency limit")
    expect(page).to have_no_text("ready job ahead")

    SolidQueue::Job.where(class_name: CanonicalCatalogJob.name).destroy_all
    request.update!(due_at: 10.minutes.from_now)
    Turbo::StreamsChannel.broadcast_refresh_to(request, method: :morph, scroll: :preserve)
    expect(page).to have_text("No investigation attempt is scheduled.")
    expect(page).to have_no_css(".investigation-progress")

    request.dispatch
    Turbo::StreamsChannel.broadcast_refresh_to(request, method: :morph, scroll: :preserve)
    expect(page).to have_css(state, exact_text: "Waiting to retry")
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: "dark" } ])
    expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
    verify_investigation_state_colors("retrying")
    capture_resolution("investigation-retry-mobile-dark")

    SolidQueue::ScheduledExecution.sole.update!(scheduled_at: 10.minutes.ago)
    Turbo::StreamsChannel.broadcast_refresh_to(request, method: :morph, scroll: :preserve)
    expect(page).to have_text("The attempt is due and no dispatcher has a current heartbeat.")
    expect(page).to have_no_css(".investigation-progress")

    request.update!(due_at: 1.second.ago)
    CanonicalCatalog::Processor.new(request, session_factory: ->(*) { CatalogFixtures::Session.new }).call do
      Turbo::StreamsChannel.broadcast_refresh_to(request, method: :morph, scroll: :preserve)
      expect(page).to have_css(state, exact_text: "Investigating")
      verify_investigation_state_colors("investigating")
      page.execute_script("window.investigationConsumer = document.querySelector(arguments[0]).subscription.consumer; window.investigationConsumer.disconnect()", stream)
      expect(page).to have_no_css("#{stream}[connected]", visible: :all)
    end
    expect(request.reload.state).to eq("imported")
    expect(page).to have_css(state, exact_text: "Investigating")
    page.execute_script("window.investigationConsumer.connect()")
    expect(page).to have_css(".resolution-choice", text: "Signals")
    expect(page).to have_no_css(".investigation-badge", exact_text: "Investigation complete")
    expect(page).to have_css('[aria-label="Original release"]', text: "You can resolve the recording without adding a release.")
    expect(page).to have_button("Resolve recording only")
    expect(page).to have_no_css(".investigation-progress")
    expect(page).to have_no_link("Refresh status")
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 1280, height: 800, deviceScaleFactor: 1, mobile: false)
    capture_resolution("investigation-complete", full: true)
  ensure
    CanonicalCatalogJob.queue_adapter = prior_adapter if prior_adapter
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
    browser&.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  it "automatically shows pending release verification when the saved recording has no complete release evidence" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "catalog-pending", lastfm_username: "catalog-pending")
    observation = catalog_observation(user)
    catalog_assessment(observation)
    sign_in(user)
    visit resolution_surface_path(observation)
    click_button "Resolve recording only"
    expect(page).to have_text("Recording decision saved.")
    expect(page).to have_css("turbo-cable-stream-source[connected]", visible: :all)
    expect(page).to have_css(".review-catalog-context", text: "Checking recording metadata")

    provider = CatalogFixtures::Session.new
    allow(provider).to receive(:edition).and_return(provider.edition.merge("media" => []))
    allow(RecordingResolution::ProviderSession).to receive(:new).and_return(provider)
    request = CatalogImport.find_by!(kind: CatalogImport::RECORDING_METADATA)
    CanonicalCatalogJob.perform_now(request.id)
    expect(request.reload.state).to eq("imported")
    expect(Release.count).to eq(0)
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
    expect(page).to have_text("No investigation attempt is scheduled.")
    capture_resolution("pending-desktop")

    request = CatalogImport.where(kind: RecordingResolution::Investigation::KIND).sole
    CanonicalCatalog::Processor.new(request, session_factory: ->(*) { CatalogFixtures::Session.new }).call
    visit page.current_url
    click_link "Review evidence"
    expect(page).to have_css(".review-candidate.recommended")
    expect(page).to have_text("2 matching observations")
    find(".review-candidate[open] .review-checked-appearance summary").click
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
    expect(page).to have_css(".investigation-badge", exact_text: "Needs review")
    expect(page).to have_css(".resolution-choice", count: 2)
    all(".resolution-choice").last.send_keys(:enter)
    expect(page).to have_css(".resolution-choice[aria-current]", count: 1)
    expect(page).to have_current_path(/candidate=#{alternate["id"]}/)
    expect(page).to have_no_css(".review-score")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
    capture_resolution("ambiguous-mobile")

    visit resolution_surface_path(observation, assessment: assessment.id)
    find_button("Resolve recording only").send_keys(:enter)
    expect(page).to have_css(".review-state", text: "Resolved")
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
    expect(page).to have_text("No investigation attempt is scheduled.")
    expect(page).to have_no_text("Provider calls")

    request = CatalogImport.find_by!(kind: RecordingResolution::Investigation::KIND)
    request.update!(state: "failed", attempts: 5, request_count: 5, failure: "musicbrainz throttled (503)")
    visit page.current_url
    within(".review-heading") do
      expect(all("dt").map(&:text)).to eq([ "Artist string", "Album string" ])
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
      expect(page).to have_button("Resolve recording only")
      expect(page).to have_text("Future exact matches inherit this decision")
      expect(page).to have_no_css(".review-tracks li")
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
    expect(page).to have_text("1 individual override preserved")
    click_button "Resolve recording only"
    expect(page).to have_text("Recording decision saved.")
    expect(page).to have_css(".review-state", exact_text: "Resolved")
    click_link "Review evidence"
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
      expect(page).to have_no_css(".review-track-match")
      expect(page).to have_button("Resolve this observation")
      expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
      capture_resolution(mobile ? "bad-days-mobile" : "bad-days-desktop")
    end
    expect(RecordingResolution::Ledger.effective(user).find(play.id).effective_recording_id).to be_nil
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
    browser&.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  def verify_recording_choice_states(width, mode)
    selected = find(".resolution-choice[aria-current]")
    other = find(".resolution-choice:not([aria-current])", match: :first)
    initial = [ selected, other ].map { |link| recording_choice_paint(link) }
    expect(initial.map { |paint| paint.fetch("border") }.uniq.size).to eq(2)
    expect(initial.all? { |paint| paint.fetch("contrast") >= 4.5 }).to be(true)

    if width == 1440
      [ [ other, "hover" ], [ selected, "selected-hover" ] ].each do |link, name|
        before = recording_choice_paint(link)
        link.hover
        after = recording_choice_paint(link)
        expect(after.fetch("wash")).not_to eq("none")
        expect(after.except("wash")).to eq(before.except("wash"))
        expect(selected["aria-current"]).to eq("true")
        capture_resolution("choices-#{width}-#{mode}-#{name}", full: true)
      end
    end

    [ [ selected, "selected-focus" ], [ other, "unselected-focus" ] ].each do |link, name|
      find(".review-sections a", text: "History").send_keys(:tab)
      7.times do
        break if page.evaluate_script("document.activeElement === arguments[0]", link)

        page.driver.browser.action.send_keys(:tab).perform
      end
      expect(page.evaluate_script("document.activeElement === arguments[0] && arguments[0].matches(':focus-visible')", link)).to be(true)
      expect(page.evaluate_script("getComputedStyle(arguments[0]).outlineWidth", link)).to eq("2px")
      expect(selected["aria-current"]).to eq("true")
      capture_resolution("choices-#{width}-#{mode}-#{name}", full: true)
    end
    page.driver.browser.action.send_keys(:tab).perform
    provider_link = find(".resolution-recording-mbid:focus-visible")
    expect(provider_link["aria-label"]).to match(/MusicBrainz recording [0-9a-f-]{36}/)
  end

  def recording_choice_paint(link)
    page.evaluate_script(<<~JS, link)
      ((link) => {
        const row = getComputedStyle(link.closest("li"));
        const card = getComputedStyle(link.closest(".library-card"));
        const title = getComputedStyle(link);
        const muted = getComputedStyle(link.querySelector(".muted"));
        const source = getComputedStyle(link.parentElement.querySelector(".resolution-recording-mbid") || link.querySelector(".muted"));
        const canvas = document.createElement("canvas");
        canvas.width = canvas.height = 1;
        const pixel = canvas.getContext("2d", {willReadFrequently: true});
        const paint = color => { pixel.fillStyle = color; pixel.fillRect(0, 0, 1, 1); };
        const luminance = () => [...pixel.getImageData(0, 0, 1, 1).data].slice(0, 3).map(v => {
          v /= 255;
          return v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4;
        }).reduce((sum, v, i) => sum + v * [.2126, .7152, .0722][i], 0);
        // Bound contrast over Site Art by using its worst possible underlying pixel.
        paint(card.colorScheme === "dark" ? "#fff" : "#000");
        paint(card.backgroundColor);
        paint(row.backgroundColor);
        const background = luminance();
        const selected = link.querySelector(".resolution-selected");
        const colors = [title.color, muted.color, source.color];
        if (selected) colors.push(getComputedStyle(selected).color);
        const contrast = colors.map(color => {
          paint(color);
          const foreground = luminance();
          return (Math.max(foreground, background) + .05) / (Math.min(foreground, background) + .05);
        });
        return {
          border: row.borderInlineStartColor, wash: row.backgroundImage, contrast: Math.min(...contrast),
          title: title.color, muted: muted.color, source: source.color, linkBackground: title.backgroundColor,
          sourceBackground: source.backgroundColor, height: link.closest("li").offsetHeight
        };
      })(arguments[0])
    JS
  end

  def verify_clear_search_style
    link = find_link("Clear search")
    submit = find_button("Search")
    page.driver.browser.action.move_to(submit.native).perform
    styles = -> do
      page.evaluate_script(<<~JS, link, submit)
        ((link, submit) => {
          const style = getComputedStyle(link)
          const button = getComputedStyle(submit)
          const l = link.getBoundingClientRect()
          const s = submit.getBoundingClientRect()
          return {
            muted: style.color === getComputedStyle(link.closest("form").querySelector("label")).color ||
              style.color !== button.color,
            smaller: parseFloat(style.fontSize) < parseFloat(button.fontSize),
            centered: Math.abs(l.top + l.height / 2 - s.top - s.height / 2) < 2,
            background: style.backgroundColor,
            border: style.borderTopWidth,
            underline: style.textDecorationLine,
            focus: link.matches(":focus-visible") && style.outlineStyle === "solid"
          }
        })(arguments[0], arguments[1])
      JS
    end
    expect(styles.call).to include("muted" => true, "smaller" => true, "centered" => true,
      "background" => "rgba(0, 0, 0, 0)", "border" => "0px", "underline" => "none")
    page.driver.browser.action.move_to(link.native).perform
    expect(styles.call).to include("background" => "rgba(0, 0, 0, 0)", "underline" => "underline")
    page.driver.browser.action.move_to(submit.native).perform
    submit.send_keys(:tab)
    expect(styles.call).to include("background" => "rgba(0, 0, 0, 0)", "focus" => true)
  end

  def verify_investigation_state_colors(active)
    result = page.evaluate_script(<<~JS, active)
      ((active) => {
        const list = document.querySelector(".investigation-progress ul")
        const states = Array.from(list.children)
        const current = states.find(state => state.getAttribute("aria-current") === "true")
        const transparent = states.filter(state => getComputedStyle(state).backgroundColor === "rgba(0, 0, 0, 0)")
        const muted = getComputedStyle(document.querySelector(".resolution-review .review-observation-meta")).color
        return states.map(state => state.dataset.state).join(",") === "queued,investigating,retrying,complete,review" &&
          current.dataset.state === active && transparent.length === 4 && !transparent.includes(current) &&
          transparent.every(state => getComputedStyle(state).color === muted) &&
          !list.querySelector("a, button")
      })(arguments[0])
    JS
    expect(result).to be(true)
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
        find(".shell-appearance > summary").send_keys(:enter) unless page.has_css?(".shell-appearance[open]", wait: 0)
        select mode.capitalize, from: "Appearance"
        find(".shell-appearance[open] > summary").send_keys(:enter) if page.has_css?(".shell-appearance[open]", wait: 0)
        expect(page).to have_css("html[data-appearance='#{mode}']", visible: :all)
        expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
        if section.start_with?("resolution")
          page.execute_script("window.scrollTo(0, 0)")
          capture_resolution("#{section}-#{size}-#{mode}", full: true)
        elsif section == "release"
          expect(page).to have_css("#listening-activity", text: "1 distinct resolved observation")
          capture_resolution("release-listening-#{size}-#{mode}")
        elsif section.start_with?("artist")
          expect(page).to have_css("#artist-recordings .listening-bar", text: "1")
          expect(page).to have_css("#artist-releases .listening-bar", text: "3 min")
          table_ids = page.all("main .library-card[id]").map { |card| card[:id] }
          expect(table_ids).to include("listening-history", "artist-recordings", "artist-releases")
          page.execute_script("window.scrollTo(0, 0)")
          capture_resolution("#{section}-listening-#{size}-#{mode}", full: true)
          if section == "artist-colors"
            paint = page.evaluate_script(<<~JS)
              (() => {
                const fill = document.querySelector(".identity-chart .artist-timeline-fill")
                const bar = document.querySelector("#artist-recordings .listening-bar")
                return [getComputedStyle(fill).backgroundImage, getComputedStyle(bar).backgroundImage]
              })()
            JS
            expect(paint.first).to include("linear-gradient", "rgb(162, 217, 206) 50%", "rgb(46, 134, 193) 50%")
            expect(paint.last).to eq(paint.first)
            find(".intro .identity-badge").click
            expect(page).to have_css("dialog[open] #guide-assignment")
            page.evaluate_async_script(<<~JS)
              const done = arguments[0]
              Promise.all(document.querySelector("dialog").getAnimations().map(a => a.finished)).then(() => done())
            JS
            capture_resolution("identity-correction-#{size}-#{mode}")
            click_button "Close"
          end
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
