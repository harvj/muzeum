require "rails_helper"

RSpec.describe "Site Art appearance", type: :system do
  before do
    skip "Run with BROWSER_TESTS=1 for Site Art browser verification" unless ENV["BROWSER_TESTS"] == "1"

    driven_by :selenium, using: :headless_chrome do |options|
      options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
    end
  end

  it "decodes the current theme, preserves the crop, and follows OS and explicit appearance" do
    light = "/environments/stone/limestone.jpg"
    dark = "/environments/stone/onyx.jpg"
    allow(SiteArt).to receive(:snapshot).and_return(light: light, dark: dark, favicon: "/icon.svg")
    browser = page.driver.browser
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [
      { name: "prefers-color-scheme", value: "light" },
      { name: "prefers-reduced-motion", value: "reduce" }
    ])
    visit new_session_path
    expect(page).to have_css("img.site-art-background[src='#{light}']", visible: :all)
    expect(page).to have_css("link[rel=icon][href='/icon.svg']", visible: :all)

    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: "dark" } ])
    expect(page).to have_css("img.site-art-background[src='#{dark}']", visible: :all)
    expect(browser.execute_script(<<~JS)).to eq([ "cover", "50% 50%", true, true ])
      const image = document.querySelector(".site-art-background")
      const style = getComputedStyle(image)
      return [style.objectFit, style.objectPosition, image.clientWidth === innerWidth, image.clientHeight === innerHeight]
    JS
    expect(page.evaluate_script("[innerWidth, innerHeight]")).to eq([ 390, 844 ])
    select "Light", from: "Appearance"
    expect(page).to have_css("img.site-art-background[src='#{light}']", visible: :all)
    click_button "Pause light"
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.stone-environment'), '::after').animationName")).to eq("none")
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
    browser&.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  it "keeps the local theme and branded icon when remote candidates cannot decode" do
    allow(SiteArt).to receive(:snapshot).and_return(light: "/session/new", favicon: "/session/new")
    visit new_session_path
    select "Light", from: "Appearance"
    expect(page).to have_button("Continue with harvj Auth")
    expect(page).to have_css("link[rel=icon][href*='muzeum-favicon']", count: 1, visible: :all)
    expect(page).to have_no_css("img.site-art-background", visible: :all)
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.stone-environment')).backgroundImage")).to include("limestone.jpg")
    select "Dark", from: "Appearance"
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.stone-environment')).backgroundImage")).to include("onyx.jpg")
  end
end
