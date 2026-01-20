module Clients
  class Error < StandardError; end
  class NetworkError < Error; end
  class RateLimited < Error; end
  class Unauthorized < Error; end
  class InvalidResponse < Error; end
end
