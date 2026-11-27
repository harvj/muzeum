require "rails_helper"
require_relative "../support/leisure_configurations_fixture"

RSpec.describe "Birthday configuration review", type: :system do
  include LeisureConfigurationsFixture

  it "keeps recording confirmation independent of the reviewed programs at both widths" do
    skip "Run with BROWSER_TESTS=1 for Resolution browser verification" unless ENV["BROWSER_TESTS"] == "1"

    stub_request(:get, "#{OidcClient::ISSUER}/.well-known/oauth-authorization-server").to_return(status: 503)
    driven_by :selenium, using: :headless_chrome do |options|
      options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
    end
    user = User.create!(oidc_issuer: OidcClient::ISSUER, oidc_subject: "birthday-review", lastfm_username: "birthday-review")
    fixture = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/release_reviews/birthday-293137.json").read)
    before = ENV["BIRTHDAY_CAPTURE_BEFORE"] == "1"
    evidence = fixture.fetch("evidence")
    unless before
      credits = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/discovery/blur-checked-editions.json").read).first.fetch("artist-credit")
      research = JSON.parse(Rails.root.join("docs/design/release-configurations/tracklists.json").read)
      evidence["reviewed_adjacent_programs"] = research.fetch("adjacent_program_editions")
        .select { |item| %w[b11e ea3d 7916].any? { |prefix| item.fetch("id").start_with?(prefix) } }
        .map do |item|
          source_edition(item).tap do |edition|
            edition["artist-credit"] = credits
            edition["media"].each do |medium|
              medium["tracks"].each { |track| track.fetch("recording")["artist-credit"] = credits }
            end
            edition["release-group"].merge!("primary-type" => "Single", "first-release-date" => edition["date"])
          end
        end
      evidence["reassessment"] = { "checked_at" => Time.current.utc.iso8601 }
    end
    claims = evidence.fetch("source_claims", {})
    payload = claims.merge("artist_name" => "Blur", "track_name" => "Birthday - 2012 Remaster", "album_name" => "Leisure")
    plays = 8.times.map do |offset|
      Scrobble.create!(id: 293137 + offset, user:, lastfm_account: user.source_account, played_at: (offset + 1).days.ago, payload:)
    end
    surface = RecordingResolution::Ledger.attach!(plays.first)
    group = RecordingResolution::Group.create!(surface_id: surface.id, version: RecordingResolution::Ledger::VERSION,
      claims: payload.slice(*RecordingResolution::PilotRunner::CLAIM_FIELDS))
    version = before ? fixture.fetch("version") : RecordingResolution::Assessment::INTERPRETATION_VERSION
    RecordingResolution::Assessment.create!(group_id: group.id, version:, digest: SecureRandom.hex(32), actor: "fixture", evidence:)
    session = user.sessions.create!(expires_at: 1.day.from_now, last_seen_at: Time.current, verified_at: Time.current, grant_token: "fixture")
    visit root_path
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.signed[:session_id] = session.id
    page.driver.browser.manage.add_cookie(name: "session_id", value: jar[:session_id], path: "/", http_only: true)
    browser = page.driver.browser
    [ [ 1440, 960, "desktop" ], [ 390, 844, "mobile" ] ].each do |width, height, size|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width == 390)
      visit "/resolution/293137"
      expect(page).to have_text("8 matching observations")
      if before
        expect(page).to have_css("section[aria-label='Original release']", text: "August 26, 1991")
        find("summary", text: "Alternative editions and track provenance").click
        expect(page).to have_text("Unclassified additional material")
      else
        expect(page).to have_no_css("section[aria-label='Original release']")
        expect(page).to have_text("Verified album configurations")
        expect(page).to have_text("Adjacent recording programs")
        find("summary", text: "September 24, 1991").click
        expect(page).to have_unchecked_field("Select configuration")
        check "Select configuration"
        expect(page).to have_checked_field("Select configuration")
        expect(page).to have_text("Keep configuration ·")
        expect(Release.count).to eq(0)
        uncheck "Select configuration"
        expect(page).to have_text("No pending release selections.")
        check "Select configuration"
        find("summary", text: "September 20, 1991").click
        within(find("summary", text: "September 20, 1991").find(:xpath, "..")) do
          check "Select configuration"
        end
        within(find("summary", text: "September 24, 1991").find(:xpath, "..")) do
          choose "Use as the admitted base and my preferred configuration"
          expect(page).to have_text("Album appearance")
        end
        find("summary", text: /She.s So High.*1990/).click
        check "Select independent release"
        expect(page).to have_text("Edit (Source labeled)")
        expect(Release.count).to eq(0)
        expect(page).to have_button("Resolve all 8 observations")
        expect(page).to have_text("Bang")
      end
      expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
      if ENV["BIRTHDAY_CAPTURES"]
        page.execute_script("window.scrollTo(0, 0); document.activeElement.blur();")
        dimensions = page.evaluate_script("[innerWidth, document.documentElement.scrollHeight]")
        capture = browser.execute_cdp("Page.captureScreenshot", captureBeyondViewport: true,
          clip: { x: 0, y: 0, width: dimensions.first, height: dimensions.last, scale: 1 })
        stage = before ? "before" : "after"
        File.binwrite(File.join(ENV.fetch("BIRTHDAY_CAPTURES"), "birthday-#{stage}-#{size}.png"), Base64.strict_decode64(capture.fetch("data")))
      end
    end
    unless before
      find("#confirm_recording").check if page.has_css?("#confirm_recording")
      click_button "Resolve all 8 observations"
      expect(page).to have_text("Recording and release decisions saved.")
      expect(Release.count).to eq(2)
      expect(ReleaseConfiguration.count).to eq(2)
      expect(RecordingResolution::Ledger.effective(user).where(id: plays.map(&:id)).map(&:effective_recording_id).uniq).to match([ kind_of(Integer) ])
    end
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
