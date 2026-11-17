module Clients
  class RateLimited < Error
    def initialize(seconds = nil, raw_body: nil)
      super("Last.fm request throttled", raw_body: raw_body, retry_after: seconds)
    end
  end
end
