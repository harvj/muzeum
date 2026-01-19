class ScrobbleResolver
  class Runner
    include SimpleLogger

    def self.run!(username:, limit: nil)
      new(username, limit).run!
    end

    def initialize(username, limit)
      @username = username
      @limit    = limit
    end

    attr_reader :username, :limit

    def run!
      user = User.find_by!(lastfm_username: username)

      unresolved = Scrobble
        .where(user:, recording_id: nil)
        .order(:played_at)

      unresolved = unresolved.limit(limit) if limit
      total = unresolved.count

      log "Resolving #{total} scrobbles for #{username}"

      resolved = 0

      unresolved.each do |scrobble|
        ScrobbleResolver.resolve!(scrobble)
        resolved += 1

        log_progress(resolved, total)
      end

      log "Resolution complete (#{resolved} scrobbles)"
    end

    private

    def log_progress(resolved, total)
      return unless (resolved % 100).zero?

      log "Resolved #{resolved} / #{total}"
    end
  end
end
