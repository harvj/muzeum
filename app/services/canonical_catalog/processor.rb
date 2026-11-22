module CanonicalCatalog
  class Processor
    MAX_ATTEMPTS = 5
    MAX_EDITIONS = 25

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
      when "artist_geography" then import_artist_geography
      when "assessment", "recording_investigation" then assess
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
        stopped = error.terminal || attempts >= MAX_ATTEMPTS || (%w[recording_investigation artist_geography].include?(@request.kind) && @request.created_at <= 1.day.ago)
        persist_assessment_failure(error, stopped) if @surface && !error.deferred
        @request.update!(state: stopped ? "failed" : "pending", attempts:, failure: error.deferred ? nil : error.message,
          due_at: retry_due_at(error, attempts), lease_token: nil, lease_until: nil)
      end
    end

    def retry_due_at(error, attempts)
      return error.retry_at if error.deferred

      [ error.retry_at, (2**attempts).seconds.from_now ].compact.max
    end

    def import_artist
      artist = Artist.find(@request.entity_id)
      data = @musicbrainz.catalog_artist(@session, artist.mbid)
      raise Store::Unverified, "Artist identity could not be verified" unless data && data["id"] == artist.mbid

      geography = nil
      complete do
        @store.artist(data)
        ids = Array(data["wikidata_ids"])
        if ids.any?
          geography = CatalogImport.request!("artist_geography", artist.id,
            data.slice("id", "country", "area", "begin-area", "wikidata_ids"))
        end
      end
      geography&.dispatch
    end

    def import_artist_geography
      artist = Artist.find(@request.entity_id)
      source = @request.context
      ids = Array(source["wikidata_ids"])
      raise Store::Unverified, "MusicBrainz artist identity changed" unless artist.mbid == source["id"]

      evidence = if ids.one?
        ArtistGeography.new(Clients::Wikimedia.new(@session)).call(mbid: artist.mbid, entity_id: ids.first, musicbrainz: source)
      else
        { "provider" => "wikidata", "status" => "conflicting_identifiers", "musicbrainz" => source }
      end
      complete do
        CatalogRevision.create!(entity_type: ArtistGeography::ENTITY_TYPE, entity_id: artist.id,
          catalog_import: @request, evidence: evidence.merge("requests" => @session.provenance))
      end
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
      ids = Array(data["releases"]).filter_map do |appearance|
        group = appearance["release-group"]
        classified = appearance["status"].present? && group&.fetch("primary-type", nil).present? &&
          group["first-release-date"].present?
        next if classified && !Edition.original_context?(appearance)

        id = appearance["id"]
        id if Clients::Musicbrainz::MBID.match?(id.to_s)
      end.uniq.sort
      if ids.size > MAX_EDITIONS
        return complete("incomplete", "Release memberships pending. More editions require verification than this import can check.")
      end

      pending = false
      editions = ids.filter_map do |id|
        edition = fetch_edition(id, recording_mbid: mbid)
        edition if Edition.original_context?(edition.data)
      rescue Store::Unverified
        pending = true
        nil
      end
      contexts = editions.group_by { |edition| edition.data.dig("release-group", "id") }
      pending ||= contexts.empty?
      contexts.each_value do |matches|
        signatures = matches.group_by { |edition| edition.slots.map { |slot| slot.dig(:recording, "id") } }
        base = signatures.keys.min_by(&:length)
        if signatures.keys.any? { |signature| signature.first(base.length) != base }
          pending = true
          next
        end

        base_editions = signatures.fetch(base)
        ids = base_editions.map { |edition| edition.data.fetch("id") }
        stored = Release.where(ingested_from_release_mbid: ids).order(:id).pick(:ingested_from_release_mbid)
        edition = base_editions.find { |item| item.data["id"] == stored } || base_editions.first
        checked = matches.map { |item| item.data.slice("id", "title", "date").merge("track_count" => item.slots.size) }
        locked { @store.release(edition.data, edition.slots, strict_collection: true, checked_editions: checked) }
      rescue Store::Unverified
        pending = true
      end
      pending ? complete("incomplete", "Some release memberships remain pending verification.") : complete
    end

    def fetch_edition(id, recording_mbid: nil)
      id = Store.mbid!(id)
      Edition.new(@musicbrainz.edition(@session, id, catalog: true), id, recording_mbid:)
    end

    def assess
      if @request.kind == "recording_investigation" && @request.created_at <= 1.day.ago
        return complete("failed", "Investigation expired before completion.")
      end

      @group = RecordingResolution::Group.find(@request.entity_id) if @request.kind == "recording_investigation"
      surface = RecordingResolution::Surface.find(@group ? @group.surface_id : @request.entity_id)
      user = User.find_by(id: @request.context["requester_id"])
      unless user&.login_enabled? && user.user_lastfm_accounts.active.exists?(lastfm_account_id: surface.lastfm_account_id)
        return complete("incomplete", "Archive access ended before this evidence check.")
      end

      observation = Scrobble.where(lastfm_account_id: surface.lastfm_account_id).find(@request.context.fetch("observation_id"))
      @surface = surface
      @claims = observation.payload.slice(*RecordingResolution::PilotRunner::CLAIM_FIELDS)
      if @group && (@group.claims != @claims || !RecordingResolution::Workspace.new(user).surface(observation)&.id.eql?(surface.id))
        return complete("incomplete", "Observation claims no longer match this investigation.")
      end
      @local_candidates = RecordingResolution::LocalCandidates.call(surface)
      identity = RecordingResolution::LocalCandidates.catalog_identity(surface)
      unless @request.context["refresh"] == true
        local_evidence = { "source_claims" => @claims, "candidates" => @local_candidates, "reasons" => [] }
        local_evidence["canonical_artist_mbid"] = identity[:artist_mbid] if identity[:artist_mbid]
        local_evidence.merge!(RecordingResolution::LocalCandidates.checked_edition(surface, @local_candidates))
        ranks = RecordingResolution::Ranking.call(surface, local_evidence, source_hints: true)
        return complete { write_assessment(local_evidence) } if ranks.one? && RecordingResolution::Ranking.recommended?(ranks)
      end
      @evaluator = RecordingResolution::Evaluator.new(@session, discogs: nil, workspace: true,
        review_alternative: @request.context["refresh"] == true, review_release: @request.context["release_mbid"],
        catalog_identity: identity)
      evidence = @evaluator.call(surface, @claims)
      if (manual = @request.context["manual_mbid"]).present?
        result = @musicbrainz.verify_recording(@session, manual, catalog: true)
        if (recording = result["data"])
          evidence["candidates"] = [ *evidence["candidates"], recording ]
          evidence["manually_verified_mbid"] = recording.fetch("id")
        end
      end
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
        "message" => error.message, "http_status" => error.http_status,
        "retry_exhausted" => stopped && !error.terminal).compact
      evidence["partial"] = true
      write_assessment(evidence)
    end

    def write_assessment(evidence)
      local_contexts = Array(@local_candidates).index_by { |candidate| candidate["id"] }
      provider_candidates = Array(evidence["candidates"]).map do |candidate|
        candidate.merge(local_contexts.fetch(candidate["id"], {}).slice("local_release_context"))
      end
      verified = evidence["verified_recording"]
      evidence = evidence.merge("candidates" => [ *provider_candidates, *@local_candidates ].uniq { |candidate| candidate["id"] })
      if verified && (local = local_contexts[verified["id"]])
        evidence["verified_recording"] = verified.merge(local.slice("local_release_context"))
      end
      evidence["ranking"] = RecordingResolution::Ranking.call(@surface, evidence, source_hints: true)
      evidence["ranking_version"] = evidence["ranking"].first&.fetch("version") || RecordingResolution::Ranking::VERSION
      group = @group || RecordingResolution::Group.create_or_find_by!(surface_id: @surface.id,
        version: RecordingResolution::Ledger::VERSION, claims: @claims)
      digest = Digest::SHA256.hexdigest(evidence.to_json)
      RecordingResolution::Assessment.create_or_find_by!(group_id: group.id, version: "workspace-evidence-v2", digest:) do |row|
        row.actor = "catalog_workspace"
        row.evidence = evidence.merge("requests" => @session.provenance)
      end
    end
  end
end
