require "rails_helper"
require_relative "../support/site_art_pair"

RSpec.describe "Muzeum v0.7.4 listening history visual acceptance", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 25, 20)) { example.run } }

  before do
    skip "Run with BROWSER_TESTS=1 for listening history verification" unless ENV["BROWSER_TESTS"] == "1"

    allow(SiteArt).to receive(:snapshot).and_return(SiteArtPair::SNAPSHOT)
    stub_request(:get, "#{OidcClient::ISSUER}/.well-known/oauth-authorization-server").to_return(status: 503)
    driven_by :selenium, using: :headless_chrome do |options|
      options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
    end
  end

  it "checks both orientations and records all requested calendar ranges on the frozen candidate" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "timeline-acceptance", lastfm_username: "timeline-acceptance")
    artist = Artist.create!(name: "Charli xcx", mbid: SecureRandom.uuid)
    release = Release.create!(title: "Charli", release_year: 2019, catalog_verified_at: Time.current)
    recording = Recording.create!(title: "Next Level Charli", mbid: SecureRandom.uuid, duration_ms: 158_000)
    artist.recordings << recording
    release.artists << artist
    release.catalog_track_slots.create!(recording:, title: recording.title, medium: 1, position: 1, track_mbid: SecureRandom.uuid)
    MusicalIdentityDecision.create!(entity: artist, user:, colors: %w[light-green blue])
    ReleaseRankingDecision.create!(user:, release:, included: true)

    now = Time.current.utc
    today = now.to_date
    recent = (0..88).reject { |offset| offset % 7 == 4 || offset % 11 == 6 }
    times = recent.flat_map do |offset|
      day = today - offset
      if offset.zero?
        [ now - 1.second ]
      else
        Array.new(1 + offset % 5) { |i| Time.utc(day.year, day.month, day.day, 12, i) }
      end
    end
    month = Date.new(2013, 6, 1)
    while month < (today - 92).beginning_of_month
      unless [ 2015, 2018, 2022 ].include?(month.year) || month.month % 4 == 0
        (month.month % 9 + 1).times { |i| times << Time.utc(month.year, month.month, 12, 13, i) }
      end
      month >>= 1
    end
    times.concat([ Time.utc(2024, 2, 29, 12), Time.utc(2024, 12, 28, 12),
      Time.utc(2024, 12, 30, 12), Time.utc(2024, 12, 31, 12), Time.utc(2024, 12, 31, 13) ])
    payload = { artist_name: artist.name, album_name: release.title, track_name: recording.title }
    observations = times.map do |played_at|
      Scrobble.create!(user:, lastfm_account: user.source_account, played_at:, payload:)
    end
    RecordingResolution::Ledger.record!(listener: user, scrobble: observations.first, scope: :surface,
      mode: "resolved", recording:, reason: "Disposable visual acceptance fixture")

    session = user.sessions.create!(expires_at: 1.day.from_now, last_seen_at: Time.current, verified_at: Time.current,
      grant_token: "local-visual-acceptance-fixture")
    visit root_path
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.signed[:session_id] = session.id
    browser = page.driver.browser
    browser.manage.add_cookie(name: "session_id", value: jar[:session_id], path: "/", http_only: true)

    matrix = [
      [ "artist-all-years", artist, "all", "years", :year ],
      [ "release-all-months", release, "all", "months", :month ],
      [ "recording-3y-years", recording, "3y", "years", :year, "2024-01-01", "2026-12-31" ],
      [ "artist-3y-months", artist, "3y", "months", :month, "2024-01-01", "2026-12-31" ],
      [ "release-year-months-current", release, "year", "months", :month, "2026-01-01", "2026-12-31" ],
      [ "release-year-months-previous", release, "year", "months", :month, "2025-01-01", "2025-12-31" ],
      [ "recording-year-days-leap", recording, "year", "days", :day, "2024-01-01", "2024-12-31" ],
      [ "artist-6m-months", artist, "6m", "months", :month, "2026-06-01", "2026-11-30" ],
      [ "release-6m-days", release, "6m", "days", :day, "2026-06-01", "2026-11-30" ],
      [ "recording-90d-days-current", recording, "90d", "days", :day, "2026-08-28", "2026-11-25" ],
      [ "recording-90d-days-previous", recording, "90d", "days", :day, "2026-05-30", "2026-08-27" ],
      [ "recording-30d-days-current", recording, "30d", "days", :day, "2026-10-27", "2026-11-25" ],
      [ "recording-30d-days-previous", recording, "30d", "days", :day, "2026-09-27", "2026-10-26" ]
    ]
    evidence = {}
    matrix.each do |name, entity, range, grouping, unit, start_date, end_date|
      bucket = ->(date) { date.utc.to_date.public_send("beginning_of_#{unit}").to_date }
      interval = Date.iso8601(start_date)..Date.iso8601(end_date) if start_date
      values = times.select { |time| !interval || interval.cover?(time.utc.to_date) }.tally
      counts = values.each_with_object(Hash.new(0)) { |(time, count), result| result[bucket.call(time)] += count }
      first, last = interval ? [ interval.begin, interval.end ].map { |date| date.public_send("beginning_of_#{unit}").to_date } : counts.keys.minmax
      dates = []
      date = first
      while date <= last
        dates << date.iso8601
        date = date.advance("#{unit}s": 1)
      end

      [ [ "desktop", 1440, 900, "light" ], [ "mobile", 390, 844, "dark" ] ].each do |size, width, height, theme|
        mobile = size == "mobile"
        browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile:)
        browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: theme } ])
        visit polymorphic_path(entity, range:, grouping:, start: start_date)
        if %w[90d 30d].include?(range)
          expect(page).to have_no_css("nav[aria-label='Listening history grouping']")
        else
          expect(page).to have_css("nav[aria-label='Listening history grouping'] [aria-current]", text: grouping.capitalize)
        end
        if interval
          expect(page.all(".listening-window time").map { |time| time[:datetime] }).to eq([ start_date, end_date ])
          expect(page).to have_css('button[aria-label="Next window"][disabled]') if name.end_with?("current")
        else
          expect(page).to have_no_css(".listening-window")
        end
        expect(page).to have_css(".artist-timeline + .listening-summary", text: "(all time)")
        expect(page).to have_css(".artist-timeline-fill", count: counts.size, visible: :all)
        page.evaluate_async_script("const done = arguments[0]; document.fonts.ready.then(() => requestAnimationFrame(() => done(true)))")
        layout = page.evaluate_script(<<~JS)
          (() => {
            const mobile = #{mobile}
            const plot = document.querySelector(".listening-plot")
            const slots = [...plot.querySelectorAll(".artist-timeline-column")]
            const rects = slots.map(slot => slot.getBoundingClientRect())
            const labels = [...plot.querySelectorAll(mobile ? ".listening-label-mobile" : ".listening-label-desktop")]
              .map(e => [e.dateTime, e.textContent, e.getBoundingClientRect()])
            labels.sort((a, b) => mobile ? a[2].top - b[2].top : a[2].left - b[2].left)
            const along = rect => mobile ? rect.top : rect.left
            const bars = slots.map(slot => slot.querySelector(".artist-timeline-fill"))
            const lengths = bars.map(bar => bar ? (mobile ? bar.getBoundingClientRect().width : bar.getBoundingClientRect().height) : 0)
            const widths = bars.filter(Boolean).map(bar => mobile ? bar.getBoundingClientRect().height : bar.getBoundingClientRect().width)
            const chartRect = plot.getBoundingClientRect()
            const overflow = mobile ? plot.scrollHeight > plot.clientHeight : plot.scrollWidth > plot.clientWidth
            const inactiveOverflow = mobile ? plot.scrollWidth > plot.clientWidth : plot.scrollHeight > plot.clientHeight
            const startsAtNewest = Math.abs(rects.at(-1).top - chartRect.top) < 1
            const headline = document.querySelector(".listening-history-heading h2").getBoundingClientRect()
            const controls = document.querySelector(".listening-controls").getBoundingClientRect()
            return {
              dates: slots.map(slot => slot.dataset.date), lengths, widths: [...new Set(widths)],
              stride: [...new Set(rects.slice(1).map((rect, i) => along(rect) - along(rects[i])))],
              labels: labels.map(([date, text]) => [date, text]),
              nonOverlap: labels.every((label, i) => !i || (mobile ? labels[i - 1][2].bottom <= label[2].top : labels[i - 1][2].right <= label[2].left)),
              overflow, inactiveOverflow, startsAtNewest,
              viewportFits: document.documentElement.scrollWidth <= innerWidth,
              controlsFit: mobile ? controls.top >= headline.bottom : controls.left >= headline.right
            }
          })()
        JS
        expect(layout.fetch("dates")).to eq(dates)
        expect(layout.fetch("widths")).to eq([ 8 ])
        expect(layout.fetch("stride")).to eq([ mobile ? -10 : 10 ])
        expect(layout.values_at("nonOverlap", "viewportFits", "controlsFit")).to all(be(true))
        expect(layout.fetch("inactiveOverflow")).to be(false)
        expect(layout.fetch("startsAtNewest")).to be(true) if mobile
        expect(layout.fetch("labels").size).to be < dates.size
        if grouping != "years"
          transitions = dates.grep(/-01-01$/).map { |value| [ value, value[0, 4] ] }
          expect(layout.fetch("labels")).to include(*transitions) if transitions.any?
          expect(layout.fetch("labels").reject { |date, _| date.end_with?("-01-01") }.map(&:last)).to all(match(/\A\d{2}-\d{2}\z/))
        end
        maximum_length = layout.fetch("lengths").max
        expect(maximum_length).to be <= 144 if mobile
        dates.zip(layout.fetch("lengths")).each do |date, length|
          ideal = maximum_length * counts[Date.iso8601(date)].fdiv(counts.values.max)
          expect(length).to be_within(1).of(ideal)
        end
        expect(layout.fetch("overflow")).to be(true) if name == "release-all-months" || (mobile && grouping == "days")
        evidence["#{name}-#{size}"] = {
          path: URI.parse(page.current_url).path, slots: dates.size, empty: dates.size - counts.size, range: [ dates.first, dates.last ],
          labels: layout.fetch("labels").size, year_markers: layout.fetch("labels").filter_map { |date, text| text if date.end_with?("-01-01") && text.size == 4 },
          overflow: layout.fetch("overflow") ? (mobile ? "vertical" : "horizontal") : "none",
          checked_bars: counts.size, peak: counts.values.max
        }
        screenshot(browser, "#{name}-#{size}")
        next unless name == "release-all-months"

        movement = page.evaluate_script(<<~JS)
          (() => {
            const mobile = #{mobile}
            const plot = document.querySelector(".listening-plot")
            plot.focus()
            if (mobile) plot.scrollTop = plot.scrollHeight
            else plot.scrollLeft = plot.scrollWidth
            return mobile ? plot.scrollTop : plot.scrollLeft
          })()
        JS
        expect(movement).to be > 0
        evidence["#{name}-#{size}"][:scrolled_pixels] = movement
        screenshot(browser, "#{name}-desktop-scrolled") unless mobile
      end
    end
    browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    { "year" => [ "2026-01-01", "2025-01-01" ], "3y" => [ "2024-01-01", "2023-01-01" ],
      "6m" => [ "2026-06-01", "2025-12-01" ], "90d" => [ "2026-08-28", "2026-05-30" ],
      "30d" => [ "2026-10-27", "2026-09-27" ] }.each do |range, (current, previous)|
      visit recording_path(recording, range:, start: current)
      expect(page).to have_css('button[aria-label="Next window"][disabled]')
      find('a[aria-label="Previous window"]').send_keys(:enter)
      expect(page).to have_css(".listening-window time:first-child[datetime='#{previous}']")
      page.refresh
      expect(page).to have_css(".listening-window time:first-child[datetime='#{previous}']")
      find('a[aria-label="Next window"]').click
      expect(page).to have_css(".listening-window time:first-child[datetime='#{current}']")
      page.go_back
      expect(page).to have_css(".listening-window time:first-child[datetime='#{previous}']")
    end
    visit recording_path(recording, range: "all", grouping: "days", start: "9999-01-01")
    expect(page).to have_css("nav[aria-label='Listening history grouping'] [aria-current]", exact_text: "Years")
    expect(page).to have_no_link("Days")
    click_link "Months"
    expect(page).to have_css("nav[aria-label='Listening history grouping'] [aria-current]", exact_text: "Months")
    click_link "Year"
    expect(page).to have_css("nav[aria-label='Listening history grouping'] [aria-current]", exact_text: "Months")
    click_link "Days"
    expect(page).to have_css("nav[aria-label='Listening history grouping'] [aria-current]", exact_text: "Days")
    click_link "3y"
    expect(page).to have_css("nav[aria-label='Listening history grouping'] [aria-current]", exact_text: "Years")
    expect(observations.map { |observation| observation.reload.payload }).to all(eq(payload.stringify_keys))
    if ENV["LISTENING_REVIEW_DIR"]
      File.write(File.join(ENV.fetch("LISTENING_REVIEW_DIR"), "calendar-checks.json"), JSON.pretty_generate(evidence) + "\n")
    end
  end

  def screenshot(browser, name)
    return unless ENV["LISTENING_REVIEW_DIR"]

    page.evaluate_script("window.scrollTo(0, 0)")
    page.evaluate_async_script("const done = arguments[0]; requestAnimationFrame(() => requestAnimationFrame(() => done(true)))")
    clip = browser.execute_cdp("Page.getLayoutMetrics").fetch("cssContentSize").slice("x", "y", "width", "height")
    screenshot = browser.execute_cdp("Page.captureScreenshot", format: "webp", quality: 88,
      captureBeyondViewport: true, clip: clip.merge("scale" => 1))
    File.binwrite(File.join(ENV.fetch("LISTENING_REVIEW_DIR"), "#{name}.webp"), Base64.decode64(screenshot.fetch("data")))
  end
end
