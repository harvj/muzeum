module RecordingResolution
  class ProviderError < StandardError
    attr_reader :retry_at, :terminal, :deferred, :http_status

    def initialize(message, retry_at: nil, terminal: false, deferred: false, http_status: nil)
      super(message)
      @http_status = http_status
      @retry_at = retry_at
      @terminal = terminal
      @deferred = deferred
    end
  end
end
