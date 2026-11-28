require "rails_helper"
require_relative "../support/birthday_production_fixture"

RSpec.describe "Birthday configuration review", type: :system do
  include BirthdayProductionFixture

  it "keeps recording confirmation independent of the reviewed programs at both widths" do
    skip "Run with BROWSER_TESTS=1 for Resolution browser verification" unless ENV["BROWSER_TESTS"] == "1"

    stub_request(:get, "#{OidcClient::ISSUER}/.well-known/oauth-authorization-server").to_return(status: 503)
    driven_by :selenium, using: :headless_chrome do |options|
      options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
    end
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "birthday-review", lastfm_username: "birthday-review")
    plays, = seed_birthday_review(user)
    session = user.sessions.create!(expires_at: 1.day.from_now, last_seen_at: Time.current, verified_at: Time.current, grant_token: "fixture")
    visit root_path
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.signed[:session_id] = session.id
    page.driver.browser.manage.add_cookie(name: "session_id", value: jar[:session_id], path: "/", http_only: true)
    browser = page.driver.browser
    [ [ 1440, 960 ], [ 390, 844 ] ].product([ "", "?section=evidence" ]).each do |(width, height), query|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width == 390)
      visit "/resolution/293137#{query}"
      expect(page).to have_text("8 matching observations")
      expect(page).to have_no_text("Proposed original release")
      checkbox = find_field("Birthday", type: "checkbox")
      row = checkbox.find(:xpath, "ancestor::li")
      highlight = row.style("background-color", "border-left-color")
      expect(highlight.values).to all(satisfy { |color| color != "rgba(0, 0, 0, 0)" })
      expect(checkbox).not_to be_checked
      expect(checkbox.style("border-radius")).to eq("border-radius" => "50%")
      expect(page).to have_no_button("Resolve all 8 observations")
      expect(page).to have_css(".resolution-release-evidence:not([open])")
      checkbox.send_keys(:space)
      expect(page).to have_checked_field("Birthday")
      expect(find_field("Birthday", type: "checkbox").find(:xpath, "ancestor::li")
        .style("background-color", "border-left-color")).to eq(highlight)
      expect(find_field("Birthday", type: "checkbox").style("background-color")).to eq("background-color" => "rgba(23, 24, 23, 1)")
      expect(page).to have_button("Resolve all 8 observations")
      expect(page).to have_text("Recording confirmation can proceed without a release choice.")
      find("summary", text: "Release configurations and adjacent programs").click
      expect(page).to have_text("Disputed source · August 26, 1991")
      expect(page).to have_text("September 24, 1991")
      expect(page).to have_text("September 20, 1991")
      expect(page).to have_text("August 27, 1991")
      expect(page).to have_text("Adjacent recording programs")
      expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
    end
    click_button "Resolve all 8 observations"
    expect(page).to have_text("Recording decision saved.")
    expect(Release.count).to eq(0)
    expect(RecordingResolution::Ledger.effective(user).where(id: plays.map(&:id)).map(&:effective_recording_id).uniq).to match([ kind_of(Integer) ])

    visit "/resolution/293137"
    check "Birthday"
    expect(page).to have_button("Resolve all 8 observations")
    find("summary", text: "Release configurations and adjacent programs").click
    find("summary", text: "September 24, 1991").click
    check "Select configuration"
    find("summary", text: "August 27, 1991").click
    within(find("summary", text: "August 27, 1991").find(:xpath, "..")) do
      check "Select configuration"
      choose "Use as the admitted base and my preferred configuration"
    end
    expect(page).to have_text("Admit one canonical album using the preferred configuration as its base.")
    [ /She.s So High · October/, /There.s No Other Way · April/, /Bang · July/ ].each do |caption|
      summary = find("summary", text: caption)
      summary.click
      within(summary.find(:xpath, "..")) { check "Select independent release" }
    end
    click_button "Resolve all 8 observations"
    expect(page).to have_text("Recording and release decisions saved.")
    album = Release.find_by!(title: "Leisure")
    configurations = album.release_configurations.index_by(&:source_country)
    expect(configurations.keys).to contain_exactly("GB", "US")
    expect(ReleaseConfigurationDecision.latest_for(user, [ album.id ]).sole.release_configuration).to eq(configurations.fetch("GB"))
    artist = Artist.find_by!(name: "Blur")
    visit artist_path(artist)
    within("#artist-releases") do
      expect(page).to have_link("Bang")
      expect(page).to have_link("She’s So High")
      expect(page).to have_link("There’s No Other Way")
      expect(page).to have_link("Leisure")
      expect(first("tbody tr")).to have_text("8 plays")
      expect(first("tbody tr")).to have_text("August 27, 1991")
      expect(page).to have_text("0 plays", count: 3)
    end
    expect(page).to have_link("Leisure", href: release_path(album), count: 1)
    expect(page).to have_no_css("#artist-unranked-releases")

    uk_tracks = configurations.fetch("GB").ordered_tracks
    us_ids = configurations.fetch("US").tracks.pluck("source_recording_mbid")
    uk_only = uk_tracks.find { |track| track.recording && us_ids.exclude?(track.source_recording_mbid) }.recording
    extra = Scrobble.create!(user:, lastfm_account: user.source_account, played_at: Time.current,
      payload: { "artist_name" => "Blur", "album_name" => "Leisure", "track_name" => uk_only.title })
    RecordingResolution::Ledger.record!(listener: user, scrobble: extra, scope: :scrobble,
      mode: "resolved", reason: "Disposable configuration comparison", recording: uk_only)
    visit release_path(album)
    expect(page).to have_text("9 distinct resolved observations")
    visit artist_path(artist)
    within("#artist-releases") { expect(first("tbody tr")).to have_text("9 plays") }
    visit release_path(album)
    find("summary", text: "Compare release configurations").click
    us = find("summary", text: "1991-09-24")
    us.click
    within(us.find(:xpath, "..")) { click_button "Prefer this configuration" }
    expect(page).to have_text("8 distinct resolved observations")
    expect(page).to have_text("September 24, 1991")
    visit artist_path(artist)
    within("#artist-releases") do
      expect(first("tbody tr")).to have_text("8 plays")
      expect(first("tbody tr")).to have_text("September 24, 1991")
    end
    expect(Release.where(release_group_mbid: album.release_group_mbid).count).to eq(1)
    expect(RecordingResolution::Ledger.effective(user).where(id: plays.map(&:id)).map(&:effective_recording_id).uniq)
      .to eq([ Recording.find_by!(title: "Birthday").id ])
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
