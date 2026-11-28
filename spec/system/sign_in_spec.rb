require "rails_helper"
require_relative "../support/site_art_pair"

RSpec.describe "Auth sign-in page", type: :system do
  before do
    allow(SiteArt).to receive(:snapshot).and_return(SiteArtPair::SNAPSHOT)
    if ENV["BROWSER_TESTS"] == "1"
      driven_by :selenium, using: :headless_chrome do |options|
        options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
      end
    else
      driven_by :rack_test
    end
  end

  it "protects the archive and offers only the established Auth login" do
    old = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    allow(OidcClient).to receive(:new).and_raise(OidcClient::Failure)
    visit root_path
    expect(page).to have_link("Log In", href: login_path)
    expect(page).not_to have_field("Password")
    expect(page).not_to have_content("Observed artists")
    click_link "Log In"
    expect(page).to have_content("Sign-in is temporarily unavailable")
    expect(OidcAttempt.count).to eq(0)
    if ENV["BROWSER_TESTS"] == "1"
      find(".shell-appearance summary").send_keys(:enter)
      select "Dark", from: "Appearance"
      expect(page).to have_css("html[data-appearance='dark']", visible: :all)
      click_button "Pause light"
      expect(page.evaluate_script("document.documentElement.dataset.still")).to eq("true")
    end
  ensure
    ActionController::Base.allow_forgery_protection = old unless old.nil?
  end
end
