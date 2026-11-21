class ApplicationShellRegistryRefreshJob < ApplicationJob
  def perform
    ApplicationShellRegistry.new.refresh
  rescue ApplicationShellRegistry::Invalid, JSON::ParserError, KeyError, ArgumentError, SystemCallError, OpenSSL::OpenSSLError, HTTP::Error
    Rails.logger.warn("Application Shell registry refresh failed")
  end
end
