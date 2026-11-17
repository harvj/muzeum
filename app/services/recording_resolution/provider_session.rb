require "http"
require "time"

module RecordingResolution
  class ProviderSession
    USER_AGENT = "Muzeum/1.3 (https://muzeum.fm)"
    LEASE = 2.minutes
    MAX_CACHE_ROWS = 1_000
    LIMITS = { musicbrainz: 300, discogs: 150 }.freeze
    SPACING = { musicbrainz: 1.second, discogs: 3.seconds }.freeze
    ORIGINS = { musicbrainz: "https://musicbrainz.org", discogs: "https://api.discogs.com" }.freeze

    attr_reader :provenance

    def initialize(work, token, fixture: nil)
      @work, @token, @fixture = work, token, fixture
      @pilot = Pilot.find(work.pilot_id)
      @provenance = []
      @http = HTTP.timeout(connect: 5, read: 10, write: 5)
    end

    def get(provider, path, params: {}, headers: {}, &project)
      key = Digest::SHA256.hexdigest([ "v1", @pilot.id, provider, path, params.sort ].to_json)
      cached = RequestCache.find_by(request_key: key, expires_at: Time.current..)
      return remember(provider, path, params, cached.document) if cached

      reserve!(provider)
      status, response_headers, body = fetch(provider, path, params, headers)
      document = interpret(provider, status, response_headers, body, project)
      document["retrieved_at"] = Time.current.iso8601(6)
      retain = provider == :discogs ? 30.minutes : 1.day
      @work.with_lock do
        self.class.assert_lease!(@work, @token)
        RequestCache.where(expires_at: ...Time.current).delete_all
        RequestCache.upsert({ request_key: key, expires_at: retain.from_now, document: }, unique_by: :request_key)
        RequestCache.where(request_key: RequestCache.order(expires_at: :desc, request_key: :desc).offset(MAX_CACHE_ROWS).select(:request_key)).delete_all
      end
      remember(provider, path, params, document)
    rescue HTTP::Error, JSON::ParserError, URI::InvalidURIError
      raise ProviderError, "#{provider} response unavailable"
    rescue KeyError, TypeError, NoMethodError, ArgumentError
      raise ProviderError, "#{provider} response contract mismatch"
    end

    def self.assert_lease!(work, token)
      return if work.state == "leased" && work.lease_token == token && work.lease_until.future?

      raise ActiveRecord::StaleObjectError.new(work, "resolve")
    end

    private

    def remember(provider, path, params, document)
      @provenance << { "provider" => provider, "endpoint" => path, "parameters" => params,
        "retrieved_at" => document["retrieved_at"],
        "projection_digest" => Digest::SHA256.hexdigest(document.except("retrieved_at").to_json) }
      document.except("retrieved_at")
    end

    def reserve!(provider)
      Work.transaction do
        @pilot.lock!
        @work.lock!
        self.class.assert_lease!(@work, @token)
        counter = "#{provider}_requests"
        raise ProviderError.new("#{provider} pilot request limit reached", terminal: true) if @pilot[counter] >= LIMITS.fetch(provider)

        if @pilot.live
          budget = ProviderBudget.create_or_find_by!(provider:) { |row| row.available_at = Time.current }
          budget.lock!
          if budget.available_at.future?
            raise ProviderError.new("#{provider} request deferred", deferred: true, retry_at: budget.available_at)
          end

          budget.update!(available_at: SPACING.fetch(provider).from_now)
        end
        @pilot.increment!(counter)
        @work.update!(lease_until: LEASE.from_now)
      end
    end

    def fetch(provider, path, params, headers)
      if @pilot.live
        url = "#{ORIGINS.fetch(provider)}#{path}"
        response = @http.headers({ "User-Agent" => USER_AGENT, "Accept" => "application/json" }.merge(headers))
          .get(url, params:)
        [ response.code, response.headers, response.to_s ]
      else
        raise ProviderError.new("Fixture transport unavailable", terminal: true) unless @fixture

        @fixture.call(provider, path, params)
      end
    end

    def interpret(provider, status, headers, body, project)
      if [ 429, 503 ].include?(status)
        due = retry_time(headers["Retry-After"]) || 1.minute.from_now
        impose_cooldown(provider, due)
        raise ProviderError.new("#{provider} throttled (#{status})", retry_at: due)
      end

      if provider == :musicbrainz && [ 301, 302, 307, 308 ].include?(status)
        target = URI.join(ORIGINS.fetch(provider), headers["Location"].to_s)
        if target.scheme == "https" && target.host == "musicbrainz.org" &&
            target.path.match?(%r{\A/ws/2/recording/[0-9a-f-]{36}\z})
          return { "redirect" => target.path.split("/").last }
        end
        raise ProviderError.new("MusicBrainz returned an invalid redirect", terminal: true)
      end

      unless [ 200, 404 ].include?(status)
        raise ProviderError.new("#{provider} returned #{status}", terminal: status.between?(400, 499))
      end

      if provider == :discogs && headers["X-Discogs-Ratelimit-Remaining"] == "0"
        impose_cooldown(provider, 1.minute.from_now)
      end
      return { "status" => 404 } if status == 404

      data = JSON.parse(body)
      raise TypeError unless data.is_a?(Hash)

      { "data" => project ? project.call(data) : data }
    end

    def retry_time(value)
      return if value.blank?
      return value.to_i.seconds.from_now if value.match?(/\A[0-9]+\z/)

      [ Time.httpdate(value), Time.current ].max
    rescue ArgumentError, RangeError
      nil
    end

    def impose_cooldown(provider, due)
      return unless @pilot.live

      ProviderBudget.where(provider:).where(available_at: ...due).update_all(available_at: due)
    end
  end
end
