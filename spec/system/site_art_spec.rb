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
    visit root_path
    expect(page).to have_css("img.site-art-background[src='#{light}']", visible: :all)
    expect(page).to have_css("link[rel=icon][href='/icon.svg']", visible: :all)

    [ [ 1440, 960 ], [ 1408, 1118 ], [ 390, 844 ], [ 1920, 800 ] ].each do |width, height|
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: width < 700)
      { "light" => light, "dark" => dark }.each do |theme, source|
        browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: theme } ])
        expect(page).to have_css("img.site-art-background[src='#{source}']", visible: :all)
        expect(page.evaluate_script("[innerWidth, innerHeight]")).to eq([ width, height ])
        expect(browser.execute_script(<<~JS)).to eq([ "cover", "50% 100%", "cover", "50% 100%", "no-repeat", true, true ])
          const image = document.querySelector(".site-art-background")
          const style = getComputedStyle(image)
          const fallback = getComputedStyle(image.parentElement)
          const bounds = image.getBoundingClientRect()
          return [style.objectFit, style.objectPosition, fallback.backgroundSize, fallback.backgroundPosition,
            fallback.backgroundRepeat, bounds.left === 0 && bounds.right === innerWidth,
            bounds.top === 0 && bounds.bottom === innerHeight]
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
        regions: { top: { foreground: "#222222", text_shadow: shadow.merge(opacity_percent: 95, y_px: 2, blur_px: 3) }, bottom: { foreground: "#F5F1E9", backing: { color: "#161412", opacity_percent: 20 } } } } },
      dark: { url: dark, presentation: { foreground: "#F5EFE3" } } }
    allow(SiteArt).to receive(:snapshot) { snapshot }
    browser = page.driver.browser
    browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
      {
        const repeat = window.setInterval;
        window.setInterval = (callback, delay, ...args) => {
          if (delay === 60000) window.refreshArtwork = callback;
          return repeat(callback, delay, ...args);
        };
      }
    JS
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: "light" } ])
    visit root_path
    expect(page).to have_css("header[data-art-treatment]")
    expect(page).to have_css("img.site-art-background[src='#{light}']", visible: :all)
    expect(overlay_property("color")).to eq("rgb(34, 34, 34)")
    expect(overlay_property("color", "main .intro h1")).to eq("rgb(41, 39, 37)")
    expect(overlay_property("color", "footer span")).to eq("rgb(245, 241, 233)")
    expect(overlay_property("textShadow", "footer span")).to include("rgba(255, 248, 233, 0.3)")
    expect(overlay_property("backgroundImage", "footer span")).to eq("none")
    expect(overlay_property("textShadow")).to eq("rgba(255, 248, 233, 0.95) 0px 2px 3px")
    expect(overlay_property("backgroundImage")).to eq("none")
    expect(overlay_property("boxShadow")).to eq("none")
    expect(overlay_property("backgroundColor", "header")).to eq("rgba(255, 255, 255, 0.54)")
    expect(overlay_property("backgroundColor", "footer")).to eq("rgba(0, 0, 0, 0.57)")
    find(".harvj-wordmark").hover
    expect(overlay_property("color")).to eq("rgb(255, 255, 255)")
    expect(overlay_property("backgroundColor")).to eq("rgb(41, 45, 44)")
    expect(overlay_property("textDecorationLine")).to eq("none")
    expect(overlay_property("textShadow")).to eq("none")
    find("main h1").hover
    browser.action.send_keys(:tab).perform
    expect(page).to have_css(".harvj-wordmark:focus-visible")
    expect(overlay_property("outlineWidth")).to eq("2px")
    browser.execute_script("document.activeElement.blur()")

    browser.execute_script("window.originalArtwork = document.querySelector('.site-art-background')")
    original = snapshot
    snapshot = snapshot.merge(release: "b" * 64, light: { url: light, presentation: { foreground: "#202020",
      text_shadow: shadow, regions: { top: { text_shadow: shadow.merge(opacity_percent: 0) } } } })
    browser.execute_script("window.refreshArtwork()")
    expect(page).to have_css("header[style*='#202020']")
    expect(overlay_property("color")).to eq("rgb(32, 32, 32)")
    expect(page.evaluate_script("document.querySelector('.site-art-background') === window.originalArtwork")).to be(true)
    expect(overlay_property("textShadow")).to eq("none")

    snapshot = original
    browser.execute_script("window.refreshArtwork()")
    expect(page).to have_css("header[style*='#222222']")
    expect(page.evaluate_script("document.querySelector('.site-art-background') === window.originalArtwork")).to be(true)

    browser.execute_script(<<~JS, dark)
      const decode = HTMLImageElement.prototype.decode;
      const darkURL = arguments[0];
      HTMLImageElement.prototype.decode = function () {
        if (this.getAttribute("src") !== darkURL) return decode.call(this);
        return new Promise(resolve => {
          window.finishObsoleteDecode = resolve;
          document.body.dataset.decodePending = "";
        });
      };
      window.restoreDecode = () => { HTMLImageElement.prototype.decode = decode; };
    JS
    select "Dark", from: "Appearance"
    expect(page).to have_css("body[data-decode-pending]")
    expect(page).to have_css("img.site-art-background[src='#{light}']", visible: :all)
    expect(overlay_property("color")).to eq("rgb(34, 34, 34)")
    select "Light", from: "Appearance"
    expect(page).to have_css("html[data-appearance='light']", visible: :all)
    browser.execute_async_script("window.finishObsoleteDecode(); window.restoreDecode(); requestAnimationFrame(arguments[0]);")
    expect(page).to have_css("img.site-art-background[src='#{light}']", visible: :all)
    expect(page.evaluate_script("document.querySelector('.site-art-background') === window.originalArtwork")).to be(true)

    select "Dark", from: "Appearance"
    expect(page).to have_css("img.site-art-background[src='#{dark}']", visible: :all)
    expect(page).to have_css("header[style*='#F5EFE3']")
    expect(overlay_property("color")).to eq("rgb(245, 239, 227)")
    expect(overlay_property("color", "footer span")).to eq("rgb(245, 239, 227)")
    sign_in = "header .entity-link"
    expect(overlay_property("color", sign_in)).to eq("rgb(245, 239, 227)")
    find(sign_in).hover
    expect(overlay_property("color", sign_in)).to eq("rgb(35, 38, 37)")
    expect(overlay_property("backgroundColor", sign_in)).to eq("rgb(241, 242, 237)")
    expect(overlay_property("textDecorationLine", sign_in)).to eq("none")
    find("main h1").hover
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

  it "runs the upstream presentation and lifecycle fixtures in the rendered roles" do
    fixtures = JSON.parse(file_fixture("site_art_presentation_v1.json").read)
    records = fixtures.fetch("assets")
    palette = fixtures.fetch("legacy_palette")
    cache = SiteArt.new
    release = "f" * 64
    snapshot = { release: }
    urls = {
      "a" * 64 => "/environments/stone/limestone.jpg",
      "b" * 64 => "/environments/stone/onyx.jpg"
    }
    allow(SiteArt).to receive(:snapshot) { snapshot }
    browser = page.driver.browser
    browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
      {
        const repeat = window.setInterval;
        window.setInterval = (callback, delay, ...args) => {
          if (delay === 60000) window.refreshArtwork = callback;
          return repeat(callback, delay, ...args);
        };
      }
      const decode = HTMLImageElement.prototype.decode;
      window.artworkDecodes = 0;
      HTMLImageElement.prototype.decode = function () {
        window.artworkDecodes++;
        if (window.rejectArtworkDecode) return Promise.reject();
        return decode.call(this);
      };
    JS
    visit root_path
    select "Light", from: "Appearance"

    sequence = fixtures.fetch("sequence")
    extra_cases = %w[unknown invalid_optional legacy plain invalid_core].map do |name|
      missing = name == "invalid_core"
      { "select" => name, "image" => missing ? nil : "unknown", "treatment" => missing ? "plain" : name,
        "decodes" => sequence.last.fetch("decodes") + 1 }
    end
    (sequence + extra_cases).each do |step|
      fixture = records[step["select"]]
      record = fixtures.fetch("base_record").merge(fixture.fetch("fields")) if fixture
      manifest = { "schema_version" => 1, "commit" => "a" * 40, "release" => release,
        "assets" => fixture ? { "muzeum.background_light" => record } : {} }
      snapshot = cache.send(:validate, manifest)
      snapshot = snapshot.merge(light: snapshot.fetch(:light).merge("url" => urls.fetch(record.fetch("sha256")))) if snapshot[:light]
      browser.execute_async_script(<<~JS, !!step["reject_decode"])
        const done = arguments[1];
        window.rejectArtworkDecode = arguments[0];
        window.refreshArtwork().then(() => requestAnimationFrame(done));
      JS
      if (image = step["image"])
        digest = records.fetch(image).fetch("fields").fetch("sha256", fixtures.fetch("base_record").fetch("sha256"))
        expect(page).to have_css(".site-art-background[src='#{urls.fetch(digest)}']", visible: :all)
      else
        expect(page).to have_no_css(".site-art-background", visible: :all)
      end
      expect(page.evaluate_script("window.artworkDecodes")).to eq(step.fetch("decodes"))

      expected_roles = records.fetch(step.fetch("treatment")).fetch("expected")
      { "default" => "main", "top" => "header", "bottom" => "footer" }.each do |role, selector|
        expected = fixtures.fetch("expected_treatments").fetch(expected_roles.fetch(role))
        %w[--art-foreground --art-text-shadow --art-backing].each do |property|
          value = expected.fetch(property, "")
          value = "#292D2C" if property == "--art-foreground" && value == palette.fetch("dark")
          expect(page.evaluate_script("document.querySelector(arguments[0]).style.getPropertyValue(arguments[1])",
            selector, property)).to eq(value), "wrong #{property} for #{step["select"]} / #{role}"
        end
      end
      release = release == "f" * 64 ? "a" * 64 : "f" * 64
    end
  end

  def overlay_property(property, selector = ".harvj-wordmark")
    page.evaluate_script("getComputedStyle(document.querySelector(arguments[0]))[arguments[1]]", selector, property)
  end

  it "keeps the local theme and branded icon when remote candidates cannot decode" do
    allow(SiteArt).to receive(:snapshot).and_return(light: { url: "/", presentation: { foreground: "#123456" } }, favicon: "/")
    visit root_path
    select "Light", from: "Appearance"
    expect(page).to have_link("Log In", href: login_path)
    expect(page).to have_css("link[rel=icon][href*='muzeum-favicon']", count: 1, visible: :all)
    expect(page).to have_no_css("img.site-art-background", visible: :all)
    expect(page).to have_no_css("[data-art-treatment]")
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.stone-environment')).backgroundImage")).to include("limestone.jpg")
    select "Dark", from: "Appearance"
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.stone-environment')).backgroundImage")).to include("onyx.jpg")
  end
end
