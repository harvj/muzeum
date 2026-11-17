module Lastfm
  class Deferred < StandardError
    attr_reader :wait
    def initialize(wait)
      @wait = wait
      super("Shared Last.fm request budget deferred")
    end
  end
end
