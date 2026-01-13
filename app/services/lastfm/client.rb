module Lastfm
  class Client
    def initialize(user)
      @user = user
    end

    # TEMP: returns parsed hashes, not XML
    def recent_scrobbles(since:)
      raise NotImplementedError
    end
  end
end
