require "rails_helper"

RSpec.describe "Music table fidelity", type: :system do
  LONG_TITLE = "A Very Long Recording Title for a Late Night Listening Session, including the complete unabridged alternate take and the full session notes"
  LONG_ARTIST = "The Midnight Ensemble with the North Shore String Collective and the South Bank Players"
  LONG_RELEASE = "Studio Sessions and Early Recordings from the Complete Midnight Ensemble Archive"

  before do
    skip "Run with BROWSER_TESTS=1 for music table browser verification" unless ENV["BROWSER_TESTS"] == "1"

    driven_by :selenium, using: :headless_chrome do |options|
      options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
    end
  end

  it "keeps desktop rows aligned, discloses full titles, and links only supported catalog entities" do
    user, album, recordings = seed_library
    authenticate_fixture(user)
    viewport(1440, 960)
    visit archive_path
    expect(page).to have_css(".listening-day", count: 2)
    capture("archive-desktop-light")
    measure_rows("archive")
    expect(page).to have_css(".play-row", count: 50)
    expect(page).to have_link(LONG_TITLE, href: recording_path(recordings.first))
    expect(page).to have_link("The Smashing Pumpkins", href: artist_path(album.artists.first))
    expect(page).to have_link(album.title, href: release_path(album))
    expect(page).not_to have_link("Unresolved guest artist")
    expect(page).not_to have_link("Different reported edition", href: release_path(album))
    expect(page.evaluate_script(<<~JS)).to be(true)
      (() => {
        const rows = [...document.querySelectorAll(".play-row")];
        const heights = rows.map(row => row.getBoundingClientRect().height);
        return Math.max(...heights) - Math.min(...heights) < 1 &&
          getComputedStyle(rows[0].querySelector("time")).fontFamily.includes("monospace");
      })()
    JS

    long_title = find_link(LONG_TITLE)
    long_title.hover
    expect(page).to have_css(".plays-tooltip:popover-open", text: LONG_TITLE)
    capture("archive-desktop-hover")
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.play-recording a:hover')).backgroundColor")).not_to eq("rgba(0, 0, 0, 0)")
    find(".library-nav a", text: "Archive").hover
    find(".play-row .table-time a", match: :first).send_keys(:tab, :tab)
    expect(page).to have_css(".play-recording a:focus-visible", text: LONG_TITLE)
    expect(page).to have_css(".plays-tooltip:popover-open", text: LONG_TITLE)
    capture("archive-desktop-focus")
    page.driver.browser.action.send_keys(:escape).perform
    expect(page).not_to have_css(".plays-tooltip:popover-open")
    [ LONG_ARTIST, LONG_RELEASE ].each do |name|
      find_link(name, match: :first).hover
      expect(page).to have_css(".plays-tooltip:popover-open", text: name)
    end
    find(".library-nav a", text: "Archive").hover

    capture("archive-desktop-dark", appearance: "dark")
    viewport(390, 844)
    expect(page).to have_button("Full names")
    expect(page.evaluate_script(<<~JS)).to be(true)
      document.querySelector(".table-scroll").scrollWidth <= document.querySelector(".table-scroll").clientWidth
    JS
    capture("archive-mobile-dark", appearance: "dark")
    click_button "Full names"
    expect(page).to have_css("button[aria-pressed='true']", text: "Full names")
    expect(page.evaluate_script(<<~JS)).to be(true)
      (() => {
        const title = document.querySelector(".play-recording .play-name > a");
        return getComputedStyle(title).whiteSpace === "normal" && title.scrollWidth <= title.clientWidth &&
          title.getBoundingClientRect().height > parseFloat(getComputedStyle(title).lineHeight);
      })()
    JS
    capture("archive-mobile-full-names", appearance: "dark")
    click_link LONG_TITLE
    expect(page).to have_current_path(recording_path(recordings.first))
    expect(page).to have_link(album.title, href: release_path(album))
  end

  it "numbers a two-disc track listing continuously while retaining the stored positions" do
    user, album = seed_library
    authenticate_fixture(user)
    viewport(1440, 960)
    visit release_path(album)
    capture("release-desktop-light")
    measure_rows("release")
    expect(all(".release-tracks tbody .track-number").map(&:text)).to eq((1..28).map(&:to_s))
    expect(album.catalog_track_slots.order(:medium, :position).pluck(:medium, :position)).to eq(
      [ 1, 2 ].product((1..14).to_a)
    )
    capture("release-desktop-dark", appearance: "dark")
  end

  it "centers the shared footer at the viewport bottom or after long content in either theme" do
    user, = seed_library
    allow(SiteArt).to receive(:snapshot).and_return(
      light: "/environments/stone/limestone.jpg", dark: "/environments/stone/onyx.jpg")
    revision = "a" * 40
    metadata = Tempfile.create("muzeum-footer")
    metadata.write("#{revision} v0.2.1\n")
    metadata.flush
    allow(Rails.configuration.x).to receive(:running_revision).and_return(revision)
    allow(Rails.configuration.x).to receive(:published_release_path).and_return(Pathname(metadata.path))
    browser = page.driver.browser
    [ [ "desktop", 1440, 960 ], [ "mobile", 390, 844 ] ].each do |screen, width, height|
      viewport(width, height)
      browser.manage.delete_all_cookies
      visit new_session_path
      expect(page).to have_css(".login")
      verify_footer("short", screen, width, height)

      authenticate_fixture(user)
      visit archive_path
      expect(page).to have_css(".play-row", count: 50)
      verify_footer("long", screen, width, height)
    end
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
    metadata&.close
    File.unlink(metadata.path) if metadata
  end

  def verify_footer(length, screen, width, height)
    expect(page).to have_css("body > .site-footer", text: "© 2026 Jim Harvey · Muzeum v0.2.1", count: 1, visible: :all)
    %w[light dark].each do |appearance|
      page.execute_script(<<~JS, appearance)
        const control = document.querySelector(".controls select");
        control.value = arguments[0];
        control.dispatchEvent(new Event("change", { bubbles: true }));
        document.documentElement.dataset.still = "true";
      JS
      texture = appearance == "light" ? "limestone" : "onyx"
      expect(page).to have_css("img.site-art-background[src$='#{texture}.jpg']", visible: :all)
      measurement = page.driver.browser.execute_script(<<~JS)
        const root = document.documentElement;
        window.scrollTo(0, root.scrollHeight);
        const footer = document.querySelector(".site-footer");
        const bounds = footer.getBoundingClientRect();
        const style = getComputedStyle(footer);
        return {
          viewport: [innerWidth, innerHeight],
          overflow: root.scrollHeight - root.clientHeight,
          horizontalOverflow: root.scrollWidth - root.clientWidth,
          bottomGap: root.clientHeight - bounds.bottom,
          contentGap: bounds.top - document.querySelector("main").getBoundingClientRect().bottom,
          centerOffset: Math.abs(bounds.left + bounds.width / 2 - root.clientWidth / 2),
          alignment: style.textAlign,
          position: style.position,
          separator: style.borderTopWidth
        };
      JS
      expect(measurement).to include("viewport" => [ width, height ], "horizontalOverflow" => 0,
        "alignment" => "center", "position" => "static", "separator" => "0px")
      expect(measurement.fetch("centerOffset")).to be < 1
      expect(measurement.fetch("bottomGap").abs).to be < 1
      expect(measurement.fetch("contentGap")).to be >= 24
      expect(measurement.fetch("overflow")).to(length == "short" ? eq(0) : be > 0)

      if appearance == (screen == "desktop" ? "light" : "dark")
        capture("footer-#{length}-#{screen}-#{appearance}", appearance:)
      end
    end
  end

  def seed_library
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "table-fidelity", lastfm_username: "table-fidelity")
    artist = Artist.create!(name: "The Smashing Pumpkins", mbid: SecureRandom.uuid)
    album = Release.create!(title: "Mellon Collie and the Infinite Sadness", release_year: 1995,
      ingested_from_release_mbid: SecureRandom.uuid, catalog_verified_at: Time.current)
    album.artists << artist
    names = [ LONG_TITLE, "Tonight, Tonight", "Jellybelly", "Zero", "Here Is No Why", "Bullet with Butterfly Wings",
      "To Forgive", "An Ode to No One", "Love", "Cupid de Locke", "Galapogos", "Muzzle", "Porcelina of the Vast Oceans",
      "Take Me Down", "Where Boys Fear to Tread", "Bodies", "Thirty-Three", "In the Arms of Sleep", "1979",
      "Tales of a Scorched Earth", "Thru the Eyes of Ruby", "Stumbleine", "X.Y.U.", "We Only Come Out at Night",
      "Beautiful", "Lily (My One and Only)", "By Starlight", "Farewell and Goodnight" ]
    recordings = names.each_with_index.map do |name, index|
      recording = Recording.create!(title: name, mbid: SecureRandom.uuid, duration_ms: 145_000 + index * 6_000)
      recording.artists << artist
      album.catalog_track_slots.create!(recording:, medium: index / 14 + 1, position: index % 14 + 1,
        number: (index % 14 + 1).to_s, title: name, track_mbid: SecureRandom.uuid)
      recording
    end
    other_plays = [
      [ "Ishq", "Orchid", "Skyblue" ],
      [ "Talk Talk", "Spirit of Eden", "The Rainbow" ],
      [ LONG_ARTIST, LONG_RELEASE, "After the Last Train" ]
    ].map do |artist_name, album_name, title|
      credit = Artist.create!(name: artist_name, mbid: SecureRandom.uuid)
      release = Release.create!(title: album_name, release_year: 2001,
        ingested_from_release_mbid: SecureRandom.uuid, catalog_verified_at: Time.current)
      release.artists << credit
      recording = Recording.create!(title:, mbid: SecureRandom.uuid, duration_ms: 392_000)
      recording.artists << credit
      release.catalog_track_slots.create!(recording:, medium: 1, position: 1, title:, track_mbid: SecureRandom.uuid)
      [ recording, credit, release ]
    end
    other_groups = [ 4..8, 13..18, 21..24 ]
    64.times do |index|
      recording = index.zero? ? recordings.first : recordings[1 + (index - 1) % (recordings.size - 1)]
      credit, release = artist, album
      if (other = other_groups.index { |range| range.cover?(index % 32) })
        recording, credit, release = other_plays.fetch(other)
      end
      unresolved = index % 5 == 4
      play = user.scrobbles.create!(played_at: Time.utc(2024, 5, 21, 21, 36) - (index / 32).days - (index % 32).minutes * 5,
        payload: { artist_name: unresolved ? "Unresolved guest artist" : credit.name, track_name: recording.title,
          album_name: index == 2 ? "Different reported edition" : release.title })
      next if unresolved

      RecordingResolution::Ledger.record!(listener: user, scrobble: play, scope: :scrobble,
        mode: "resolved", reason: "Browser fixture", recording:)
    end
    [ user, album, recordings ]
  end

  def authenticate_fixture(user)
    session = user.sessions.create!(expires_at: 1.day.from_now, last_seen_at: Time.current, verified_at: Time.current,
      grant_token: "fixture")
    visit new_session_path
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.signed[:session_id] = session.id
    page.driver.browser.manage.add_cookie(name: "session_id", value: jar[:session_id], path: "/", http_only: true)
  end

  def viewport(width, height)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width < 700)
  end

  def capture(name, appearance: "light")
    page.execute_script("document.documentElement.dataset.appearance = arguments[0]; document.documentElement.dataset.still = 'true'", appearance)
    return unless ENV["MUSIC_TABLE_CAPTURES"]

    page.evaluate_async_script("const done = arguments[0]; document.fonts.ready.then(() => requestAnimationFrame(() => done(true)))")
    page.save_screenshot(File.join(ENV.fetch("MUSIC_TABLE_CAPTURES"), "#{name}.png"))
  end

  def measure_rows(section)
    return unless ENV["MUSIC_TABLE_CAPTURES"]

    rows = page.evaluate_script(<<~JS)
      [...document.querySelectorAll(".catalog-table tbody tr:not(.listening-day)")].filter(row => {
        const box = row.getBoundingClientRect();
        return box.top >= 0 && box.bottom <= innerHeight;
      }).length
    JS
    puts "#{section}: #{rows} complete music rows at 1440 × 960"
  end
end
