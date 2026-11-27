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
    [ [ 1440, 960, "desktop" ], [ 390, 844, "mobile" ] ].each do |width, height, _size|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width == 390)
      visit "/resolution/293137?section=evidence"
      expect(page).to have_text("8 matching observations")
      expect(page).to have_no_text("Proposed original release")
      checkbox = find_field("Birthday", type: "checkbox")
      expect(checkbox).not_to be_checked
      expect(checkbox.style("border-radius")).to eq("border-radius" => "50%")
      expect(page).to have_no_button("Resolve all 8 observations")
      expect(page).to have_css(".resolution-release-evidence:not([open])")
      checkbox.send_keys(:space)
      expect(page).to have_checked_field("Birthday")
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
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
