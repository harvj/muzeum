require "rails_helper"

RSpec.describe "Site Art appearance", type: :system do
  before do
    skip "Run with BROWSER_TESTS=1 for Site Art browser verification" unless ENV["BROWSER_TESTS"] == "1"

    driven_by :selenium, using: :headless_chrome do |options|
      options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
    end
  end

  it "decodes the current theme, shares the bottom-anchored crop, and follows OS and explicit appearance" do
    light = "/environments/stone/limestone.jpg"
    dark = "/environments/stone/onyx.jpg"
    allow(SiteArt).to receive(:snapshot).and_return(light: { url: light }, dark: { url: dark }, favicon: "/icon.svg")
    browser = page.driver.browser
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [
      { name: "prefers-color-scheme", value: "light" },
      { name: "prefers-reduced-motion", value: "reduce" }
    ])
    visit new_session_path
    expect(page).to have_css("img.site-art-background[src='#{light}']", visible: :all)
    expect(page).to have_css("link[rel=icon][href='/icon.svg']", visible: :all)

    [ [ 1440, 960 ], [ 390, 844 ] ].each do |width, height|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width < 700)
      { "light" => light, "dark" => dark }.each do |theme, source|
        browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: theme } ])
        expect(page).to have_css("img.site-art-background[src='#{source}']", visible: :all)
        expect(page.evaluate_script("[innerWidth, innerHeight]")).to eq([ width, height ])
        expect(browser.execute_script(<<~JS)).to eq([ "cover", "50% 100%", "cover", "50% 100%", "no-repeat", true, true ])
          const image = document.querySelector(".site-art-background")
          const style = getComputedStyle(image)
          const fallback = getComputedStyle(image.parentElement)
          return [style.objectFit, style.objectPosition, fallback.backgroundSize, fallback.backgroundPosition,
            fallback.backgroundRepeat, image.clientWidth === innerWidth, image.clientHeight === innerHeight]
        JS
      end
    end
    select "Light", from: "Appearance"
    expect(page).to have_css("img.site-art-background[src='#{light}']", visible: :all)
    click_button "Pause light"
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.stone-environment'), '::after').animationName")).to eq("none")
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
    browser&.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  it "updates treatment at the same image URL and clears it on image failure and forced colors" do
    light = "/environments/stone/limestone.jpg"
    dark = "/environments/stone/onyx.jpg"
    shadow = { color: "#FFF8E9", opacity_percent: 30, blur_px: 2, x_px: 0, y_px: 1 }
    backing = { color: "#FFF8E9", opacity_percent: 12 }
    snapshot = { release: "a" * 64,
      light: { url: light, foreground: "light", presentation: { foreground: "#292725", text_shadow: shadow, backing:,
        regions: { top: { foreground: "#222222" }, bottom: { foreground: "#F5F1E9", backing: { color: "#161412", opacity_percent: 20 } } } } },
      dark: { url: dark, presentation: { foreground: "#F5EFE3" } } }
    allow(SiteArt).to receive(:snapshot) { snapshot }
    browser = page.driver.browser
    browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
      const repeat = window.setInterval;
      window.setInterval = (callback, delay, ...args) => {
        if (delay === 60000) window.refreshArtwork = callback;
        return repeat(callback, delay, ...args);
      };
    JS
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: "light" } ])
    visit root_path
    expect(page).to have_css("header[data-art-treatment]")
    expect(page).to have_css("img.site-art-background[src='#{light}']", visible: :all)
    expect(overlay_property("color")).to eq("rgb(34, 34, 34)")
    expect(overlay_property("color", "main .intro h1")).to eq("rgb(41, 39, 37)")
    expect(overlay_property("color", "footer span")).to eq("rgb(245, 241, 233)")
    expect(overlay_property("textShadow", "footer span")).to include("rgba(255, 248, 233, 0.3)")
    expect(overlay_property("backgroundImage", "footer span")).to include("rgba(22, 20, 18, 0.2)")
    expect(overlay_property("textShadow")).to include("rgba(255, 248, 233, 0.3)")
    expect(overlay_property("backgroundImage")).to include("rgba(255, 248, 233, 0.12)")
    find(".harvj-wordmark").hover
    expect(overlay_property("color")).to eq("rgb(255, 255, 255)")
    expect(overlay_property("backgroundColor")).to eq("rgb(41, 45, 44)")
    find("main h1").hover
    browser.action.send_keys(:tab).perform
    expect(page).to have_css(".harvj-wordmark:focus-visible")
    expect(overlay_property("outlineWidth")).to eq("2px")
    browser.execute_script("document.activeElement.blur()")

    browser.execute_script("window.originalArtwork = document.querySelector('.site-art-background')")
    snapshot = snapshot.merge(release: "b" * 64, light: { url: light, presentation: { foreground: "#202020" } })
    browser.execute_script("window.refreshArtwork()")
    expect(page).to have_css("header[style*='#202020']")
    expect(overlay_property("color")).to eq("rgb(32, 32, 32)")
    expect(page.evaluate_script("document.querySelector('.site-art-background') === window.originalArtwork")).to be(true)
    expect(overlay_property("textShadow")).to eq("none")

    select "Dark", from: "Appearance"
    expect(page).to have_css("img.site-art-background[src='#{dark}']", visible: :all)
    expect(page).to have_css("header[style*='#F5EFE3']")
    expect(overlay_property("color")).to eq("rgb(245, 239, 227)")
    expect(overlay_property("color", "footer span")).to eq("rgb(245, 239, 227)")
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "forced-colors", value: "active" } ])
    expect(overlay_property("backgroundImage")).to eq("none")
    expect(overlay_property("color")).not_to eq("rgb(245, 239, 227)")
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    browser.execute_script("document.querySelector('.site-art-background').dispatchEvent(new Event('error'))")
    expect(page).to have_no_css("[data-art-treatment]")
    expect(page).to have_no_css("img.site-art-background", visible: :all)
    expect(overlay_property("color")).to eq("rgb(241, 242, 237)")

    snapshot = snapshot.merge(release: "c" * 64, dark: { url: light, presentation: { foreground: "#F0E8DF" } })
    browser.execute_script("window.refreshArtwork()")
    expect(page).to have_css("img.site-art-background[src='#{light}']", visible: :all)
    expect(page).to have_css("header[style*='#F0E8DF']")
    expect(overlay_property("color")).to eq("rgb(240, 232, 223)")
  end

  def overlay_property(property, selector = ".harvj-wordmark")
    page.evaluate_script("getComputedStyle(document.querySelector(arguments[0]))[arguments[1]]", selector, property)
  end

  it "keeps the local theme and branded icon when remote candidates cannot decode" do
    allow(SiteArt).to receive(:snapshot).and_return(light: { url: "/session/new", presentation: { foreground: "#123456" } }, favicon: "/session/new")
    visit new_session_path
    select "Light", from: "Appearance"
    expect(page).to have_button("Continue with harvj Auth")
    expect(page).to have_css("link[rel=icon][href*='muzeum-favicon']", count: 1, visible: :all)
    expect(page).to have_no_css("img.site-art-background", visible: :all)
    expect(page).to have_no_css("[data-art-treatment]")
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.stone-environment')).backgroundImage")).to include("limestone.jpg")
    select "Dark", from: "Appearance"
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.stone-environment')).backgroundImage")).to include("onyx.jpg")
  end
end
