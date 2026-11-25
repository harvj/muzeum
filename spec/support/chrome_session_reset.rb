require "capybara/selenium/driver"
require "capybara/selenium/driver_specializations/chrome_driver"

module ChromeSessionReset
  def reset!
    super
  rescue Selenium::WebDriver::Error::InvalidArgumentError => error
    # Chrome 158 rejects Capybara 3.40's wildcard storage origin.
    raise unless error.message.include?("* is not a valid URL")

    # A fresh browser clears storage for both Muzeum and the test Auth origin.
    quit
  end
end

Capybara::Selenium::Driver::ChromeDriver.prepend(ChromeSessionReset)
