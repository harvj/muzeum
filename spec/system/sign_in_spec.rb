require "rails_helper"

RSpec.describe "Local sign in", type: :system do
  before do
    if ENV["BROWSER_TESTS"] == "1"
      driven_by :selenium, using: :headless_chrome do |options|
        options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
      end
    else
      driven_by :rack_test
    end
  end

  it "signs in and out through the Rails views" do
    User.create!(email_address: "listener@example.com", password: "a long secret password", activated_at: Time.current)
    visit root_path
    expect(page).to have_content("Sign in to Muzeum")
    fill_in "Email address", with: "listener@example.com"
    fill_in "Password", with: "a long secret password"
    click_button "Sign in"
    expect(page).to have_content("Signed in as listener@example.com")
    click_button "Sign out"
    expect(page).to have_content("Sign in to Muzeum")
    visit root_path
    expect(page).to have_content("Sign in to Muzeum")
  end
end
