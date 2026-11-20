source "https://rubygems.org"

ruby "3.4.13"

gem "rails", "~> 8.1.4", ">= 8.1.4.1"
gem "propshaft"
gem "pg", "~> 1.1"
gem "puma", "~> 8.1"
gem "http", "~> 6.0"

gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 2.2"
# image_processing 2 makes processors optional; retain Rails' vips backend.
gem "ruby-vips", "~> 2.3", require: false

group :development, :test do
  gem "dotenv-rails"
  gem "rspec-rails"
  gem "pry"

  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  # Retain encrypted OpenSSH key support after removing Kamal's dependency chain.
  gem "bcrypt_pbkdf", require: false
  gem "ed25519", "~> 1.4", require: false
  gem "capistrano", "~> 3.19", require: false
  gem "capistrano-rails", require: false
  gem "web-console"
end

group :test do
  gem "webmock"
  gem "capybara"
  gem "selenium-webdriver"
end

gem "openid_connect", "~> 2.3"
