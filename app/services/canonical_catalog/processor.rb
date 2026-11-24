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

      yield if block_given?

      @session = @session_factory.call(@request, @token)
      @store = Store.new(@request, @session)
      case @request.kind
      when "recording", CatalogImport::RECORDING_METADATA then import_recording
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

      assessment = RecordingResolution::Assessment.find_by(id: @request.context["assessment_id"])
      publication = assessment&.evidence&.dig("recording_publications", mbid, "earliest_publication")
      locked { @store.recording(data, expected: mbid, publication:) }
      return complete if @request.kind == CatalogImport::RECORDING_METADATA || @request.context.key?("assessment_id")

      ids = Array(data["releases"]).filter_map do |appearance|
        group = appearance["release-group"]
        classified = appearance["status"].present? && group&.fetch("primary-type", nil).present? &&
          group["first-release-date"].present?
        next if classified && !Edition.collection_context?(appearance)

        id = appearance["id"]
        id if Clients::Musicbrainz::MBID.match?(id.to_s)
      end.uniq.sort
      if ids.size > MAX_EDITIONS
        return complete("incomplete", "Release memberships pending. More editions require verification than this import can check.")
      end

      pending = false
      editions = ids.filter_map do |id|
        edition = fetch_edition(id, recording_mbid: mbid)
        edition if Edition.collection_context?(edition.data)
      rescue Store::Unverified
        pending = true
        nil
      end
      contexts = editions.group_by { |edition| edition.data.dig("release-group", "id") }
      pending ||= contexts.empty?
      remaining_editions = MAX_EDITIONS - ids.size
      contexts.each do |group, matches|
        unless matches.any? { |edition| Edition.original_context?(edition.data) }
          original_date = matches.first.data.dig("release-group", "first-release-date")
          originals = @musicbrainz.collection_editions(@session, group, limit: MAX_EDITIONS).select do |row|
            row["status"] == "Official" && row["date"] == original_date
          end
          if originals.size > remaining_editions
            raise Store::Unverified, "Original tracklists exceed the evidence budget"
          end
          remaining_editions -= originals.size
          matches += originals.map { |row| fetch_edition(row.fetch("id")) }.select do |edition|
            edition.data.dig("release-group", "id") == group && Edition.original_context?(edition.data)
          end
        end
        construction = Construction.new(matches, recording_mbid: mbid)
        edition = construction.base
        pending ||= (edition.slots + construction.additional_slots).none? { |slot| slot.dig(:recording, "id") == mbid }
        locked do
          @store.release(edition.data, edition.slots, strict_collection: true,
            checked_editions: construction.appearances, additional_slots: construction.additional_slots)
        end
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
        catalog_identity: identity, origins: false)
      evidence = @evaluator.call(surface, @claims) do |recording_evidence|
        if (manual = @request.context["manual_mbid"]).present?
          result = @musicbrainz.verify_recording(@session, manual, catalog: true)
          if (recording = result["data"])
            recording_evidence["candidates"] = [ *recording_evidence["candidates"], recording ]
            recording_evidence["manually_verified_mbid"] = recording.fetch("id")
          end
        end
      end
      investigate_publication(surface, evidence)
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

    def investigate_publication(surface, evidence)
      # Appearance evidence belongs to the investigation, but it cannot decide
      # which otherwise plausible identities get a publication lookup.
      independent = evidence.except("edition", "slots", "review_tracklists").merge(
        "candidates" => Array(evidence["candidates"]).map { |candidate| candidate.except("release_discovery", "local_release_context", "releases") })
      ids = RecordingResolution::Ranking.call(surface, independent, source_hints: true).filter_map do |rank|
        inputs = rank.fetch("inputs")
        rank["recording_mbid"] if inputs.dig("title", "state") == "positive" && inputs.dig("artist_name", "state") == "positive"
      end.first(RecordingResolution::Workspace::REVIEW_CANDIDATES)
      # A checked track caption can identify a split movement even when its
      # recording title omits the section prefix used in the source.
      caption_ids = RecordingResolution::Ranking.call(surface, evidence, source_hints: true).filter_map do |rank|
        inputs = rank.fetch("inputs")
        appearance = inputs.dig("catalog_release_appearance", "provenance")
        if appearance&.fetch("relationship", nil) == "matching_catalog_caption" &&
            inputs.dig("title", "state") == "positive" && inputs.dig("artist_name", "state") == "positive"
          rank["recording_mbid"]
        end
      end
      ids = (ids | caption_ids).first(RecordingResolution::Workspace::REVIEW_CANDIDATES)
      ids |= Array(evidence["manually_verified_mbid"])

      previous = RecordingResolution::Assessment.where(group_id: @group&.id, created_at: 1.day.ago..)
        .where("evidence ? 'recording_publications'").order(id: :desc).pick(:evidence) || {}
      saved = previous.fetch("recording_publications", {}).slice(*ids).reject do |_, history|
        history["checked_at"].to_s < 1.day.ago.utc.iso8601 || !history.key?("verified_recording") || history["pending"] || history["appearance_browse_incomplete"] || Array(history["pending_groups"]).any? ||
          (Array(history["original_groups"]).any? && !history.key?("edition_coverage"))
      end
      # Only reuse completed, recent histories and their checked source editions.
      groups = saved.values.flat_map { |history| Array(history["original_groups"]) }
      previous_editions = Array(previous["construction_editions"]).select { |edition| groups.include?(edition.dig("release-group", "id")) }
      retained = (previous_editions + Array(evidence["construction_editions"])).uniq { |edition| edition["id"] }
      evidence["recording_publications"] = saved
      evidence["construction_editions"] = retained
      evidence["reused_publication_requests"] = (Array(previous["reused_publication_requests"]) + Array(previous["requests"])).uniq if saved.any?
      result = RecordingResolution::RecordingOrigins.new(@musicbrainz, @session).call(ids - saved.keys, retained:)
      evidence.merge!(result.merge("recording_publications" => saved.merge(result.fetch("recording_publications"))))
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
