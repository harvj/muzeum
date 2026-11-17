module Clients
  class Error < StandardError
    attr_reader :raw_body, :retry_after
    def initialize(message = nil, raw_body: nil, retry_after: nil)
      @raw_body, @retry_after = raw_body, retry_after
      super(message || self.class.name)
    end
  end
end
