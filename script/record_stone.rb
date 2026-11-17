# Actual Chrome screenshots sampled at 4 fps, encoded in-browser at normal speed.
# No credentials, application state, or production access is involved.
require "bundler/setup"
require "capybara"
require "selenium-webdriver"
require "rack/files"
require "base64"
Capybara.register_driver(:stone_recording) do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end
session = Capybara::Session.new(:stone_recording, Rack::Files.new("public"))
$stdout.sync = true
begin
  session.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 1280, height: 720, deviceScaleFactor: 1, mobile: false)
  %w[light dark].each do |mode|
    session.visit("/environments/stone/preview.html?mode=#{mode}&recording=1")
    session.execute_script("return Promise.all([...document.images].map(i=>i.decode()))")
    frames = []
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    92.times do |i|
      wait = started + i * 0.25 - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      sleep(wait) if wait.positive?
      frames << session.driver.browser.execute_cdp("Page.captureScreenshot", format: "jpeg", quality: 78).fetch("data")
    end
    puts "Captured 23 seconds of actual #{mode} browser rendering."
    session.driver.browser.manage.timeouts.script_timeout = 40
    encoded = session.driver.browser.execute_async_script(<<~JS, frames)
      const frames=arguments[0],done=arguments[arguments.length-1];
      (async()=>{
        const canvas=document.createElement('canvas');canvas.width=1280;canvas.height=720;
        const ctx=canvas.getContext('2d');const stream=canvas.captureStream(4);
        const recorder=new MediaRecorder(stream,{mimeType:'video/webm;codecs=vp9',videoBitsPerSecond:2200000});
        const chunks=[];recorder.ondataavailable=e=>{if(e.data.size)chunks.push(e.data)};
        const finished=new Promise(resolve=>recorder.onstop=resolve);recorder.start();
        const start=performance.now();
        for(let i=0;i<frames.length;i++){
          const img=new Image();img.src='data:image/jpeg;base64,'+frames[i];await img.decode();
          const wait=start+i*250-performance.now();if(wait>0)await new Promise(r=>setTimeout(r,wait));
          ctx.drawImage(img,0,0);
        }
        await new Promise(r=>setTimeout(r,250));recorder.stop();await finished;
        const reader=new FileReader();reader.onload=()=>done(reader.result.split(',')[1]);reader.readAsDataURL(new Blob(chunks,{type:'video/webm'}));
      })().catch(e=>done({error:e.message}));
    JS
    raise encoded.inspect unless encoded.is_a?(String)
    File.binwrite("docs/p1.1d/previews/#{mode}-illumination.webm", Base64.decode64(encoded))
    puts "Saved #{mode} browser recording."
  end
ensure
  session.driver.quit
end
