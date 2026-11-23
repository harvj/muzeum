require "http"
require "time"

module RecordingResolution
  class ProviderSession
    USER_AGENT = "Muzeum/1.3 (https://muzeum.fm)"
    LEASE = 2.minutes
    MAX_CACHE_ROWS = 1_000
    MAX_WIKIMEDIA_CACHE_ROWS = 200
    LIMITS = { musicbrainz: 300, discogs: 150 }.freeze
    WIKIMEDIA = %i[wikidata commons].freeze
    SPACING = { musicbrainz: 1.second, discogs: 3.seconds, wikidata: 1.second, commons: 1.second }.freeze
    ORIGINS = { musicbrainz: "https://musicbrainz.org", discogs: "https://api.discogs.com",
      wikidata: "https://www.wikidata.org", commons: "https://commons.wikimedia.org" }.freeze

    attr_reader :provenance, :current_request

    def initialize(work, token, fixture: nil, catalog: false)
      @work, @token, @fixture = work, token, fixture
      @catalog = catalog
      @pilot = Pilot.find(work.pilot_id) unless catalog
      @provenance = []
      @http = HTTP.timeout(connect: 5, read: 10, write: 5)
    end

    def get(provider, path, params: {}, headers: {}, projection: nil, &project)
      if provider == :discogs && live?
        raise ProviderError.new("Discogs API has been retired", terminal: true)
      end
      query = canonical_query(params)
      @current_request = { "provider" => provider.to_s, "endpoint" => path, "parameters" => query }
      # The public search projection is context-free. Catalog release lookups use a shared, versioned projection.
      scope = if @catalog && WIKIMEDIA.include?(provider)
        [ "catalog-wikimedia-v1", projection ]
      elsif @catalog && provider == :musicbrainz && path == "/ws/2/recording"
        "catalog-recording-search-v1"
      elsif @catalog && provider == :musicbrainz && path.start_with?("/ws/2/release/") && query["inc"] == "recordings+artist-credits+release-groups+url-rels"
        "catalog-release-tracklist-v1"
      elsif @catalog && provider == :musicbrainz && (path == "/ws/2/release" && (query.key?("recording") || query.key?("release-group")) ||
          path.start_with?("/ws/2/recording/") || path.start_with?("/ws/2/release/") && query["inc"].to_s.include?("genres+tags"))
        "catalog-publication-evidence-v1"
      else
        @catalog ? [ "catalog-v1", @work.id ] : [ "v1", @pilot.id ]
      end
      key = Digest::SHA256.hexdigest([ scope, provider, path, query.sort ].to_json)
      cached = RequestCache.find_by(request_key: key, expires_at: Time.current..)
      return remember(provider, path, query, cached.document) if cached

      reserve!(provider)
      status, response_headers, body = fetch(provider, path, live? ? query : params, headers)
      document = interpret(provider, status, response_headers, body, project)
      document["retrieved_at"] = Time.current.iso8601(6)
      document["cache_family"] = "wikimedia" if WIKIMEDIA.include?(provider)
      retain = WIKIMEDIA.include?(provider) ? 7.days : (provider == :discogs ? 30.minutes : 1.day)
      @work.with_lock do
        self.class.assert_lease!(@work, @token, state: @catalog ? "refreshing" : "leased")
        RequestCache.where(expires_at: ...Time.current).delete_all
        RequestCache.upsert({ request_key: key, expires_at: retain.from_now, document: }, unique_by: :request_key)
        family = if WIKIMEDIA.include?(provider)
          RequestCache.where("document->>'cache_family' = 'wikimedia'")
        else
          RequestCache.where("document->>'cache_family' IS NULL")
        end
        capacity = WIKIMEDIA.include?(provider) ? MAX_WIKIMEDIA_CACHE_ROWS : MAX_CACHE_ROWS
        RequestCache.where(request_key: family.order(expires_at: :desc, request_key: :desc).offset(capacity).select(:request_key)).delete_all
      end
      remember(provider, path, query, document)
    rescue HTTP::Error, JSON::ParserError, URI::InvalidURIError
      raise ProviderError, "#{provider} response unavailable"
    rescue KeyError, TypeError, NoMethodError, ArgumentError
      raise ProviderError, "#{provider} response contract mismatch"
    end

    def self.assert_lease!(work, token, state: "leased")
      return if work.state == state && work.lease_token == token && work.lease_until.future?

      raise ActiveRecord::StaleObjectError.new(work, "resolve")
    end

    private

    def canonical_query(params)
      params.each_with_object({}) do |(key, value), query|
        name = key.to_s
        if query.key?(name) && !query.fetch(name).eql?(value)
          raise ProviderError.new("Conflicting query parameter: #{name}", terminal: true)
        end

        query[name] = value
      end
    end

    def remember(provider, path, params, document)
      @provenance << { "provider" => provider, "endpoint" => path, "parameters" => params,
        "retrieved_at" => document["retrieved_at"],
        "projection_digest" => Digest::SHA256.hexdigest(document.except("retrieved_at", "cache_family").to_json) }
      document.except("retrieved_at", "cache_family")
    end

    def reserve!(provider)
      return reserve_catalog!(provider) if @catalog

      Work.transaction do
        @pilot.lock!
        @work.lock!
        self.class.assert_lease!(@work, @token)
        counter = "#{provider}_requests"
        raise ProviderError.new("#{provider} pilot request limit reached", terminal: true) if @pilot[counter] >= LIMITS.fetch(provider)

        reserve_provider!(provider) if live?
        @pilot.increment!(counter)
        @work.update!(lease_until: LEASE.from_now)
      end
    end

    def reserve_catalog!(provider)
      @work.with_lock do
        self.class.assert_lease!(@work, @token, state: "refreshing")
        if @work.request_count >= 32
          raise ProviderError.new("Catalog import request limit reached", terminal: true)
        end

        reserve_provider!(provider)
        @work.update!(request_count: @work.request_count + 1, lease_until: LEASE.from_now)
      end
    end

    def reserve_provider!(provider)
      budget = ProviderBudget.create_or_find_by!(provider:) { |row| row.available_at = Time.current }
      budget.lock!
      if budget.available_at.future?
        raise ProviderError.new("#{provider} request deferred", deferred: true, retry_at: budget.available_at)
      end

      budget.update!(available_at: SPACING.fetch(provider).from_now)
    end

    def live?
      @catalog || @pilot.live
    end

    def fetch(provider, path, params, headers)
      if live?
        url = "#{ORIGINS.fetch(provider)}#{path}"
        response = @http.headers({ "User-Agent" => USER_AGENT, "Accept" => "application/json" }.merge(headers))
          .get(url, params:)
        [ response.code, response.headers, WIKIMEDIA.include?(provider) ? bounded_wikimedia_body(response) : response.to_s ]
      else
        raise ProviderError.new("Fixture transport unavailable", terminal: true) unless @fixture

        @fixture.call(provider, path, params)
      end
    end

    def bounded_wikimedia_body(response)
      body = +""
      response.body.each do |chunk|
        if body.bytesize + chunk.bytesize > 4.megabytes
          response.body.connection.close
          raise ProviderError.new("Wikimedia response exceeds the enrichment limit", terminal: true)
        end

        body << chunk
      end
      body
    end

    def interpret(provider, status, headers, body, project)
      if [ 429, 503 ].include?(status)
        due = retry_time(headers["Retry-After"]) || 1.minute.from_now
        impose_cooldown(provider, due)
        raise ProviderError.new("#{provider} throttled (#{status})", retry_at: due, http_status: status)
      end

      if provider == :discogs && status.between?(500, 599)
        due = retry_time(headers["Retry-After"])
        impose_cooldown(provider, due) if due
        raise ProviderError.new("#{provider} returned #{status}", retry_at: due, http_status: status)
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

      if WIKIMEDIA.include?(provider) && data["error"]
        if data.dig("error", "code") == "maxlag"
          due = retry_time(headers["Retry-After"]) || 1.minute.from_now
          impose_cooldown(provider, due)
          raise ProviderError.new("#{provider} reports replication lag", retry_at: due)
        end
        raise ProviderError.new("#{provider} API rejected the request", terminal: true)
      end

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
      return unless live?

      ProviderBudget.where(provider:).where(available_at: ...due).update_all(available_at: due)
    end
  end
end
