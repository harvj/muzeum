require "rails_helper"

RSpec.describe "Auth sign-in page", type: :system do
  before do
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
    visit root_path
    expect(page).to have_content("Sign in to Muzeum")
    expect(page).to have_button("Continue with harvj Auth")
    expect(page).not_to have_field("Password")
    expect(page).not_to have_content("Observed artists")
    click_button "Continue with harvj Auth"
    expect(page).to have_content("Sign-in is temporarily unavailable")
    expect(OidcAttempt.count).to eq(1)
    if ENV["BROWSER_TESTS"] == "1"
      select "Dark", from: "Appearance"
      expect(page.evaluate_script("document.documentElement.dataset.appearance")).to eq("dark")
      click_button "Pause light"
      expect(page.evaluate_script("document.documentElement.dataset.still")).to eq("true")
    end
  ensure
    ActionController::Base.allow_forgery_protection = old unless old.nil?
  end
end
