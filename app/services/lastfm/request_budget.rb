module Lastfm
  class RequestBudget
    def self.interval
      1.0 / Float(ENV.fetch("LASTFM_REQUESTS_PER_SECOND", "1")).clamp(0.01, 1.0)
    end

    def self.acquire!(now: nil)
      IngestionBudget.find_or_create_by!(name: "lastfm") { |record| record.next_request_at = Time.at(0) }
      IngestionBudget.transaction do
        budget = IngestionBudget.lock.find_by!(name: "lastfm")
        now ||= IngestionBudget.connection.select_value("SELECT clock_timestamp()").to_time
        raise Deferred, budget.next_request_at - now if budget.next_request_at > now
        budget.update!(next_request_at: now + interval)
      end
    end

    def self.cooldown!(seconds)
      IngestionBudget.find_by!(name: "lastfm").with_lock do
        # Reload under the shared row lock.
        record = IngestionBudget.find_by!(name: "lastfm")
        record.update!(next_request_at: [ record.next_request_at, Time.current + [ seconds, 1 ].max ].max)
      end
    end
  end
end
