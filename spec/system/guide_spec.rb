require "rails_helper"

RSpec.describe "Muzeum Guide", type: :system, if: ENV["BROWSER_TESTS"] == "1" do
  before do
    driven_by :selenium, using: :headless_chrome do |options|
      options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
    end
  end

  it "preserves the page when opened, follows a section link, and restores focus on Escape" do
    visit root_path
    click_link "Guide"
    expect(page).to have_css("dialog[open]")
    within("dialog") { click_link "Canonical releases" }
    expect(page.evaluate_script("location.hash")).to eq("#guide-releases")
    find("#guide-releases").send_keys(:escape)
    expect(page).to have_no_css("dialog[open]")
    expect(page.evaluate_script("document.activeElement.textContent")).to eq("Guide")
    expect(page).to have_current_path(root_path)
  end
  it "opens the palette without horizontal overflow on desktop and mobile" do
    browser = page.driver.browser
    [ [ "desktop", 1440, 960 ], [ "mobile", 390, 844 ] ].each do |size, width, height|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: size == "mobile")
      %w[light dark].each do |mode|
        browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: mode } ])
        visit root_path
        click_link "Guide"
        expect(page).to have_css("dialog[open] .guide-palette .identity-swatch", count: 12)
        expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
        page.evaluate_async_script(<<~JS)
          const done = arguments[0]
          Promise.all(document.querySelector("dialog").getAnimations().map(a => a.finished)).then(() => done())
        JS
        expect(page.evaluate_script('getComputedStyle(document.querySelector(".identity-light-green:not(.identity-swatch-dual)")).backgroundColor')).to eq("rgb(162, 217, 206)")
        expect(page.evaluate_script('document.querySelector("dialog").getBoundingClientRect().right')).to be_within(1).of(width)
        if ENV["P151_PREVIEW_DIR"]
          page.save_screenshot(File.join(ENV.fetch("P151_PREVIEW_DIR"), "guide-#{size}-#{mode}.png"))
        end
        click_button "Close"
      end
    end
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
    browser&.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end
end
