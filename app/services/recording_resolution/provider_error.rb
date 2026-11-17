module RecordingResolution
  class ProviderError < StandardError
    attr_reader :retry_at, :terminal, :deferred

    def initialize(message, retry_at: nil, terminal: false, deferred: false)
      super(message)
      @retry_at = retry_at
      @terminal = terminal
      @deferred = deferred
    end
  end
end
