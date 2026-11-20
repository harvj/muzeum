require "rails_helper"
require_relative "../support/artist_geography_fixture"

RSpec.describe "Verified artist geography", type: :system do
  include ArtistGeographyFixture

  before do
    skip "Run with BROWSER_TESTS=1 for geographic presentation verification" unless ENV["BROWSER_TESTS"] == "1"

    driven_by :selenium, using: :headless_chrome do |options|
      options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
    end
  end

  it "shows Scotland and Chicago flags with accessible names and handles missing flags across layouts" do
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "geography-browser")
    session = user.sessions.create!(expires_at: 7.days.from_now, last_seen_at: Time.current, verified_at: Time.current,
      grant_token: "browser-test-fixture")
    visit root_path
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.signed[:session_id] = session.id
    page.driver.browser.manage.add_cookie(name: "session_id", value: jar[:session_id], path: "/", http_only: true)

    boards = save_artist("Boards of Canada", ArtistGeographyFixture::BOARDS, "Q722778", "GB")
    wilco = save_artist("Wilco", ArtistGeographyFixture::WILCO, "Q637771", "US")
    flags_unavailable = ArtistGeographyFixture::Session.new
    flags_unavailable.fixture["commons"] = { "query" => { "pages" => [] } }
    missing = artist_origin(ArtistGeographyFixture::WILCO, "Q637771", "US", session: flags_unavailable)

    browser = page.driver.browser
    timings = []
    [ [ 1440, 960 ], [ 390, 844 ] ].product(%w[light dark]).each do |(width, height), theme|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width < 700)
      browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: theme } ])
      visit artist_path(boards)
      expect(page).to have_link("Scotland", href: "https://www.wikidata.org/wiki/Q22")
      expect(page).to have_css('img[alt="Flag of Scotland"][src$="/Flag_of_Scotland.svg"]', visible: :all)
      expect(page).to have_text("Founded in Edinburgh", normalize_ws: true)

      visit artist_path(wilco)
      expect(page).to have_link("Chicago", href: "https://www.wikidata.org/wiki/Q1297")
      expect(page).to have_css('img[alt="Flag of Chicago"][src$="/Flag_of_Chicago%2C_Illinois.svg"]', visible: :all)
      expect(page).to have_text(/Chicago.*Illinois.*United States/, normalize_ws: true)
      timings << page.evaluate_script("performance.getEntriesByType('navigation')[0].responseStart")
      expect(page.evaluate_script("innerWidth")).to eq(width)
      expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
    end

    warn "Artist page responseStart samples (ms): #{timings.map(&:round).join(', ')}" if ENV["MEASURE_WIKIMEDIA"]

    save_evidence(wilco, missing)
    visit artist_path(wilco)
    expect(page).to have_link("Chicago")
    expect(page).to have_no_css('img[alt="Flag of Chicago"]', visible: :all)
    expect(page).to have_no_css('img[alt="Flag of United States"]', visible: :all)
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
    browser&.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  def save_artist(name, mbid, entity, country)
    Artist.create!(name:, mbid:, country:).tap { |artist| save_evidence(artist, artist_origin(mbid, entity, country)) }
  end

  def save_evidence(artist, evidence)
    request = CatalogImport.create!(kind: "artist_geography", entity_id: artist.id, state: "imported", due_at: Time.current)
    CatalogRevision.create!(catalog_import: request, entity_type: CanonicalCatalog::ArtistGeography::ENTITY_TYPE, entity_id: artist.id, evidence:)
  end
end
