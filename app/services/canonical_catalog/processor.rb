module CanonicalCatalog
  class Processor
    MAX_ATTEMPTS = 5
    MAX_EDITIONS = 3

    def initialize(request, session_factory: nil)
      @request = request
      @session_factory = session_factory || ->(row, token) { RecordingResolution::ProviderSession.new(row, token, catalog: true) }
      @musicbrainz = Clients::Musicbrainz.new
    end

    def call
      @token = claim
      return unless @token

      @session = @session_factory.call(@request, @token)
      @store = Store.new(@request, @session)
      case @request.kind
      when "recording" then import_recording
      when "release" then import_release
      when "artist" then import_artist
      when "assessment" then assess
      end
    rescue RecordingResolution::ProviderError => error
      retry_or_fail(error)
    rescue Store::Unverified, KeyError, TypeError => error
      complete("incomplete", error.is_a?(Store::Unverified) ? error.message : "Provider evidence is incomplete")
    rescue ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout
      retry_or_fail(RecordingResolution::ProviderError.new("Catalog write was interrupted; retry pending"))
    rescue ActiveRecord::StaleObjectError
      nil
    end

    private

    def claim
      @request.with_lock do
        return unless (@request.state == "pending" && @request.due_at <= Time.current) ||
          (@request.state == "refreshing" && @request.lease_until <= Time.current)

        SecureRandom.uuid.tap do |token|
          @request.update!(state: "refreshing", lease_token: token, lease_until: RecordingResolution::ProviderSession::LEASE.from_now)
        end
      end
    end

    def locked
      @request.with_lock do
        RecordingResolution::ProviderSession.assert_lease!(@request, @token, state: "refreshing")
        yield
      end
    end

    def complete(state = "imported", failure = nil)
      locked do
        yield if block_given?
        @request.update!(state:, failure:, lease_token: nil, lease_until: nil)
      end
    end

    def retry_or_fail(error)
      locked do
        attempts = @request.attempts + (error.deferred ? 0 : 1)
        stopped = error.terminal || attempts >= MAX_ATTEMPTS
        persist_assessment_failure(error, stopped) if @surface && !error.deferred
        @request.update!(state: stopped ? "failed" : "pending", attempts:, failure: error.deferred ? nil : error.message,
          due_at: error.retry_at || (2**attempts).seconds.from_now, lease_token: nil, lease_until: nil)
      end
    end

    def import_artist
      artist = Artist.find(@request.entity_id)
      data = @musicbrainz.catalog_artist(@session, artist.mbid)
      raise Store::Unverified, "Artist identity could not be verified" unless data && data["id"] == artist.mbid

      complete { @store.artist(data) }
    end

    def import_release
      release = Release.find(@request.entity_id)
      edition = fetch_edition(release.ingested_from_release_mbid)
      complete { @store.release(edition.data, edition.slots) }
    end

    def import_recording
      recording = Recording.find(@request.entity_id)
      mbid = recording.mbid
      data = @musicbrainz.verify_recording(@session, mbid, catalog: true)["data"]
      raise Store::Unverified, "Selected recording identity could not be verified" unless data && data["id"] == mbid

      locked { @store.recording(data, expected: mbid) }
      context = @request.context
      return complete if context.blank?

      edition = select_edition(data, context)
      return complete("incomplete", "Release association pending. Select a verified edition to continue.") unless edition

      comparison = edition_comparison(edition, mbid)
      if context["edition_mbid"].blank? && comparison["status"].in?(%w[contradicts mixed])
        return complete("incomplete", "Release association pending because Discogs editions disagree.")
      end

      complete { @store.release(edition.data, edition.slots, comparison:) }
    end

    def select_edition(recording, context)
      mbid = recording.fetch("id")
      explicit = context["edition_mbid"]
      return fetch_edition(explicit, recording_mbid: mbid) if explicit.present?

      album = context["album"]
      return if album.blank?

      appearances = Array(recording["releases"])
      matching = appearances.select { |release| release["title"] == album }
      ids = [ context["observed_edition_mbid"], *matching.pluck("id") ].compact.uniq
      return if ids.size > MAX_EDITIONS && context["observed_edition_mbid"].blank?

      # The exact observed edition can supply strong context even when the title has many variants.
      editions = ids.first(MAX_EDITIONS).filter_map do |id|
        edition = fetch_edition(id, recording_mbid: mbid)
        edition if edition.original_context?(album)
      rescue Store::Unverified
        nil
      end
      # Compare collection content rather than interpreting a provider group as a collection identity.
      albums = editions.select { |edition| edition.data.dig("release-group", "primary-type") == "Album" }
      editions = albums if albums.any?
      collections = editions.group_by { |edition| edition.slots.map { |slot| slot.dig(:recording, "id") } }
      collections.values.first.first if collections.one?
    end

    def fetch_edition(id, recording_mbid: nil)
      id = Store.mbid!(id)
      Edition.new(@musicbrainz.edition(@session, id, catalog: true), id, recording_mbid:)
    end

    def edition_comparison(edition, mbid)
      discogs = discogs_client
      return { "status" => "unavailable" } unless discogs

      data = edition.data
      selected = edition.slots.find { |slot| slot.dig(:recording, "id") == mbid }
      credit = Array(data["artist-credit"]).map { |entry| "#{entry["name"]}#{entry["joinphrase"]}" }.join
      surface = RecordingResolution::Surface.new(artist: credit, album: data["title"], track: selected.fetch(:title))
      evidence = {}
      RecordingResolution::DiscogsEvidence.new(discogs, expanded: true).compare(surface, data, evidence)
      evidence
    end

    def discogs_client
      return unless ENV.values_at("DISCOGS_CONSUMER_KEY", "DISCOGS_CONSUMER_SECRET").all?(&:present?)

      Clients::Discogs.new(@session, live: true)
    end

    def assess
      surface = RecordingResolution::Surface.find(@request.entity_id)
      user = User.find_by(id: @request.context["requester_id"])
      unless user&.login_enabled? && user.user_lastfm_accounts.active.exists?(lastfm_account_id: surface.lastfm_account_id)
        return complete("incomplete", "Archive access ended before this evidence check.")
      end

      observation = Scrobble.where(lastfm_account_id: surface.lastfm_account_id).find(@request.context.fetch("observation_id"))
      @surface = surface
      @claims = observation.payload.slice(*RecordingResolution::PilotRunner::CLAIM_FIELDS)
      @evaluator = RecordingResolution::Evaluator.new(@session, discogs: discogs_client, workspace: true)
      evidence = @evaluator.call(surface, @claims)
      edition_slots = Array(evidence["slots"])
      candidates = RecordingResolution::Workspace.candidate_evidence(evidence)
      supported = candidates.select do |candidate|
        candidate["title"] == surface.track &&
          Array(candidate["artist-credit"]).map { |credit| "#{credit["name"]}#{credit["joinphrase"]}" }.join == surface.artist &&
          edition_slots.any? { |slot| slot["recording_mbid"] == candidate["id"] && slot["title"] == surface.track }
      end
      evidence["review_mbid"] = supported.first["id"] if supported.one? && evidence.dig("edition", "title") == surface.album
      complete { write_assessment(evidence) }
    end

    def persist_assessment_failure(error, stopped)
      evidence = @evaluator&.evidence || { "source_claims" => @claims, "reasons" => [], "reason_details" => {} }
      code = error.terminal ? "provider_request_stopped" : "provider_temporarily_unavailable"
      evidence["reasons"] << code
      evidence["reason_details"][code] = (@session.current_request || {}).merge(
        "message" => error.message, "retry_exhausted" => stopped && !error.terminal)
      evidence["partial"] = true
      write_assessment(evidence)
    end

    def write_assessment(evidence)
      group = RecordingResolution::Group.create_or_find_by!(surface_id: @surface.id,
        version: RecordingResolution::Ledger::VERSION, claims: @claims)
      digest = Digest::SHA256.hexdigest(evidence.to_json)
      RecordingResolution::Assessment.create_or_find_by!(group_id: group.id, version: "workspace-evidence-v1", digest:) do |row|
        row.actor = "catalog_workspace"
        row.evidence = evidence.merge("requests" => @session.provenance)
      end
    end
  end
end
