module Clients
  class Error < StandardError; end
  class NetworkError < StandardError; end
  class RateLimited < StandardError; end
  class Unauthorized < StandardError; end
  class InvalidResponse < StandardError; end
end
