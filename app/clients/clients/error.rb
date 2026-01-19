module Clients
  class Error < StandardError
    attr_reader :status, :body

    def initialize(message, status:, body:)
      super(message)
      @status = status
      @body = body
    end
  end

  class NetworkError < Error; end
  class RateLimited < Error; end
  class Unauthorized < Error; end
  class InvalidResponse < Error; end
end
