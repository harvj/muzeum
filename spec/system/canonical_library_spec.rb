require "rails_helper"
require_relative "../support/catalog_fixtures"
require_relative "../support/guilt_show_fixture"
require_relative "../support/narrow_stairs_fixture"

RSpec.describe "Canonical library resolution workflow", type: :system do
  include CatalogFixtures
  include GuiltShowFixture
  include NarrowStairsFixture

  before do
    skip "Run with BROWSER_TESTS=1 for canonical workspace browser verification" unless ENV["BROWSER_TESTS"] == "1"

    stub_request(:get, "#{OidcClient::ISSUER}/.well-known/oauth-authorization-server").to_return(status: 503)

    driven_by :selenium, using: :headless_chrome do |options|
      options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
    end
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
          expect(first).to have_css(".listening-bar:not([data-identity-first])", text: "4m")
          expect(second).to have_text("0s")
          expect(page).to have_no_css(".intro h1")
        end
        capture_resolution("catalog-#{section}-#{width}-#{theme}") if section != "recordings"
        fill_in "Search #{section}", with: "zero-play"
        click_button "Search"
        expect(page).to have_link("Clear search")
        find_link("Clear search").send_keys(:enter)
        expect(page).to have_no_link("Clear search")
        expect(page).to have_css(".catalog-table tbody tr", count: section == "recordings" ? 1 : 2)
      end

      visit archive_path(q: "bad days")
      expect(page).to have_css(".play-row", count: 1, text: pending.payload.fetch("track_name"))
      capture_resolution("catalog-archive-search-#{width}-#{theme}")
      find_link("Clear search").send_keys(:enter)
      expect(page).to have_no_link("Clear search")
      expect(page).to have_css(".play-row", count: 2)
      expect(find(".play-row", text: "bad days")).to have_no_css(".play-badge .identity-swatch")
      expect(find(".play-row", text: recording.title)).to have_css('.play-length + .play-badge [data-identity-first="pink"][data-identity-second="gray"]')
      expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
      capture_resolution("catalog-archive-#{width}-#{theme}")

      visit artist_path(artist)
      find("summary", text: "Listening history data").click
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
        find(".harvj-session > summary").send_keys(:enter) unless page.has_css?(".harvj-session[open]", wait: 0)
        select mode.capitalize, from: "Appearance"
        find(".harvj-session[open] > summary").send_keys(:enter) if page.has_css?(".harvj-session[open]", wait: 0)
        expect(page.evaluate_script("document.documentElement.dataset.appearance")).to eq(mode)
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
    select = find("select#construct_release")
    select.find("option[value='#{original["id"]}']").select_option
    expect(page).to have_css(".resolution-context .review-tracks", count: 1)
    select.find("option[value='#{other["id"]}']").select_option
    expect(page).to have_css(".resolution-context .review-tracks", count: 1)
    expect(find(".resolution-context .review-tracks li", match: :first)).to have_text(tracks.first.fetch("title"))
    expect(page).to have_css('[aria-label="Resolution preview"] li', text: "1 new release", count: 1)
    capture_resolution("release-choice-mobile-dark", full: true)

    click_button "Resolve this observation"
    expect(page).to have_text("Recording decision saved.")
    expect(Release.sole.ingested_from_release_mbid).to eq(other["id"])
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
    expect(page).to have_text("Like a Man Possessed · 2004-08-21")
    capture_resolution("guilt-show-additional-tracks")
    expect(page).to have_text("0 distinct resolved observations")
    find("summary", text: "Tracks counted in listening totals").click
    within(find(".release-track-preferences li", text: "Like a Man Possessed")) { click_button "Include" }
    expect(page).to have_text("3 distinct resolved observations")
    browser = page.driver.browser
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: "dark" } ])
    capture_resolution("guilt-show-track-preferences", full: true)
    browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    within(find(".release-track-preferences li", text: "Like a Man Possessed")) { click_button "Exclude" }
    expect(page).to have_text("0 distinct resolved observations")
    expect(ReleaseTrackListeningDecision.order(:id).pluck(:included)).to eq([ true, false ])
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

    click_link "Releases"
    click_link "Night Drive"
    expect(page).to have_text(/track listing/i)
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
    within("#artist-recordings") { click_link "Title" }
    expect(page).to have_css("#artist-recordings tbody tr:first-child", text: "Different Song")
    expect(page).to have_css("#artist-releases .listening-bar", text: "3m")
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

  it "refreshes an investigation outcome over Action Cable without reloading manually" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "live-investigation", lastfm_username: "live-investigation")
    observation = catalog_observation(user)
    sign_in(user)
    visit resolution_surface_path(observation)
    expect(page).to have_css(".investigation-progress", text: "Queued")
    expect(page).to have_css("turbo-cable-stream-source[connected]", visible: :all)
    capture_resolution("investigation-queued")

    provider = CatalogFixtures::Session.new
    allow(RecordingResolution::ProviderSession).to receive(:new).and_return(provider)
    request = CatalogImport.where(kind: RecordingResolution::Investigation::KIND).sole
    CanonicalCatalogJob.perform_now(request.id)
    expect(request.reload.state).to eq("imported")
    expect(page).to have_css(".investigation-badge", text: /Investigation complete|Needs review/)
    expect(page).to have_css(".resolution-choice", text: "Signals")
    expect(page).to have_no_css(".investigation-progress")
    capture_resolution("investigation-complete")
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
    expect(page).to have_text("Investigation pending")
    capture_resolution("pending-desktop")

    request = CatalogImport.where(kind: RecordingResolution::Investigation::KIND).sole
    CanonicalCatalog::Processor.new(request, session_factory: ->(*) { CatalogFixtures::Session.new }).call
    click_link "Refresh status"
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
    expect(page).to have_css(".investigation-progress", text: "Queued")
    expect(page).to have_no_text("Provider calls")

    request = CatalogImport.find_by!(kind: RecordingResolution::Investigation::KIND)
    request.update!(state: "failed", attempts: 5, request_count: 5, failure: "musicbrainz throttled (503)")
    click_link "Refresh status"
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
        if section.start_with?("resolution")
          page.execute_script("window.scrollTo(0, 0)")
          capture_resolution("#{section}-#{size}-#{mode}", full: true)
        elsif section == "release"
          expect(page).to have_css("#listening-activity", text: "1 distinct resolved observation")
          capture_resolution("release-listening-#{size}-#{mode}")
        elsif section.start_with?("artist")
          expect(page).to have_css("#artist-recordings .listening-bar", text: "1")
          expect(page).to have_css("#artist-releases .listening-bar", text: "3m")
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
