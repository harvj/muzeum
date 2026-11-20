module RecordingResolution
  class ReleaseBatch
    VERSION = "release-tracklist-batch-v1"
    MAX_OBSERVATIONS = 50
    MAX_PROPOSALS = 15
    MAX_SURFACES = 200
    MAX_POSITIONS = 8
    PURPOSE = :release_tracklist_review
    Claims = Data.define(:artist, :album, :track)
    MATCH_SQL = <<~SQL.freeze
      (SELECT matches.*
       FROM jsonb_to_recordset(CAST(? AS jsonb)) AS claims(artist text, album text, track text)
       CROSS JOIN LATERAL (
         SELECT scrobbles.* FROM scrobbles
         WHERE lastfm_account_id = ?
           AND #{Ledger::EXACT_KEY_SQL} = resolution_surface_key(claims.artist, claims.album, claims.track)
         ORDER BY id DESC LIMIT ?
       ) AS matches) AS scrobbles
    SQL

    attr_reader :tracklist, :anchor

    def initialize(listener, anchor, release)
      @listener = listener
      @anchor = anchor
      @tracklist = ReleaseTracklist.new(release)
      @workspace = Workspace.new(listener)
      verify_anchor!
    end

    def proposals
      candidates = candidates_by_surface
      return [] if candidates.empty?

      claims = candidates.keys.map { |tuple| Claims.new(*tuple).to_h }
      rows = Scrobble.from(Arel.sql(MATCH_SQL, claims.to_json, anchor.lastfm_account_id, MAX_OBSERVATIONS))
        .order(id: :desc).limit(MAX_OBSERVATIONS).to_a
      effective = Ledger.effective(@listener).where(id: rows.map(&:id)).index_by(&:id)
      previously_reviewed = Decision.where(user_id: @listener.id, scrobble_id: rows.map(&:id)).distinct.pluck(:scrobble_id).to_set
      rows.filter_map do |row|
        state = effective[row.id]
        next unless state && state.effective_recording_id.nil? && state.effective_recording_decision_id.nil? && !previously_reviewed.include?(row.id)

        tuple = row.payload.values_at(*Ledger::PAYLOAD_FIELDS)
        slots = candidates[tuple]
        proposal(row, slots) if slots
      end.group_by { |entry| entry.fetch("ranking") }.values.map do |group|
        group.first.merge("observation_ids" => group.flat_map { |entry| entry.fetch("observation_ids") })
      end.sort_by { |entry| [ -entry.fetch("ranking").first.fetch("score"), -entry.fetch("observation_ids").size ] }.first(MAX_PROPOSALS)
    end

    def token(proposals)
      verifier.generate({ "version" => VERSION, "listener_id" => @listener.id, "anchor_id" => anchor.id,
        "anchor_decision_id" => @anchor_decision.id, "release" => tracklist.evidence, "shown_at" => Time.current.utc.iso8601(6),
        "proposals" => proposals }, purpose: PURPOSE, expires_in: 20.minutes)
    end

    def confirm!(token, choices, comment:)
      snapshot = verifier.verified(token.to_s, purpose: PURPOSE)
      unless snapshot && snapshot.values_at("version", "listener_id", "anchor_id", "anchor_decision_id", "release") ==
          [ VERSION, @listener.id, anchor.id, @anchor_decision.id, tracklist.evidence ]
        raise ArgumentError, "Review expired or changed"
      end
      displayed = snapshot.fetch("proposals")
      raise ArgumentError if choices.empty? || comment.to_s.length > 500
      raise ArgumentError unless choices.keys.all? { |key| /\A(?:0|[1-9]\d*)\z/.match?(key) && key.to_i < displayed.size }

      Decision.transaction do
        @listener.lock!
        tracklist.release.lock!
        raise ArgumentError unless ReleaseTracklist.new(tracklist.release).evidence == snapshot.fetch("release")

        verify_anchor!
        raise ArgumentError unless @anchor_decision.id == snapshot.fetch("anchor_decision_id")
        @listener.managed_archive_grants.lock.find_by!(lastfm_account_id: anchor.lastfm_account_id)
        choices.sum do |index, choice|
          apply!(displayed.fetch(index.to_i), choice, snapshot, comment)
        end
      end
    end

    private

    def verifier
      Rails.application.message_verifier(:release_tracklist_batch)
    end

    def verify_anchor!
      resolved = Ledger.effective(@listener).find(anchor.id)
      @anchor_decision = Decision.find_by(id: resolved.effective_recording_decision_id, user_id: @listener.id,
        actor: "listener", mode: "resolved")
      unless @anchor_decision && !@anchor_decision.evidence.key?("release_batch") &&
          tracklist.slots.any? { |slot| slot.recording_id == resolved.effective_recording_id }
        raise ArgumentError, "A previously confirmed recording on this release is required"
      end
      raise ArgumentError unless @listener.managed_archive_grants.exists?(lastfm_account_id: anchor.lastfm_account_id)
    end

    def candidates_by_surface
      tracklist.slots.each_with_object({}) do |slot, surfaces|
        slot.recording.artists.each do |artist|
          key = [ artist.name, tracklist.release.title, slot.title ]
          (surfaces[key] ||= []) << slot
        end
      end.first(MAX_SURFACES).to_h
    end

    def proposal(row, slots)
      return if slots.size > MAX_POSITIONS
      return if slots.all? { |slot| slot.recording_id == @anchor_decision.recording_id }

      source = row.payload.slice(*PilotRunner::CLAIM_FIELDS)
      release_claim = source["album_mbid"]
      return if release_claim.present? && !tracklist.release.ingested_from_release_mbid.casecmp?(release_claim.to_s)

      context = { "revision_id" => tracklist.revision.id, "independent_decision_id" => @anchor_decision.id }
      candidates = slots.map do |slot|
        support = slot.recording_id == @anchor_decision.recording_id ? context.except("independent_decision_id") : context
        ReleaseTracklist.candidate(slot.recording, support)
      end
      claimed = source["track_mbid"]
      id_match = candidates.find { |candidate| candidate["id"].casecmp?(claimed.to_s) }
      return if claimed.present? && !id_match
      anchor_mbid = slots.find { |slot| slot.recording_id == @anchor_decision.recording_id }&.recording&.mbid
      return if id_match && id_match["id"] == anchor_mbid

      surface = Claims.new(*row.payload.values_at(*Ledger::PAYLOAD_FIELDS))
      evidence = { "source_claims" => source, "candidates" => candidates, "verified_recording" => id_match }
      if release_claim.present?
        evidence["edition"] = { "title" => tracklist.release.title }
        evidence["slots"] = slots.map { |slot| { "recording_mbid" => slot.recording.mbid, "title" => slot.title } }
      end
      ranking = Ranking.call(surface, evidence)
      return if ranking.empty?

      input = ranking.first
      selectable = (id_match || (release_claim.present? && ranking.one?)) &&
        input.fetch("inputs").values.none? { |factor| factor["state"] == "contradictory" }
      rejectable = ranking.one? || ranking[0]["score"] > ranking[1]["score"]
      { "observation_ids" => [ row.id ], "ranking" => ranking, "selectable" => !!selectable, "rejectable" => rejectable, "positions" => slots.map do |slot|
        { "recording_mbid" => slot.recording.mbid, "medium" => slot.medium, "position" => slot.position }
      end }
    end

    def apply!(proposal, choice, snapshot, comment)
      return 0 if choice.blank?
      raise ArgumentError unless %w[accept reject].include?(choice)
      raise ArgumentError if choice == "accept" && !proposal.fetch("selectable")
      raise ArgumentError if choice == "reject" && !proposal.fetch("rejectable")

      ranking = proposal.fetch("ranking")
      mbid = ranking.first.fetch("recording_mbid")
      recording = Recording.find_by!(mbid:) if choice == "accept"
      ids = proposal.fetch("observation_ids")
      observations = Ledger.effective(@listener).where(id: ids, lastfm_account_id: anchor.lastfm_account_id).to_a
      # Refuse stale confirmations atomically, including new inherited assignments or deferred decisions.
      unless observations.size == ids.size && observations.all? { |row| row.effective_recording_id.nil? && row.effective_recording_decision_id.nil? }
        raise ArgumentError, "An affected observation changed"
      end

      observations.each do |observation|
        Ledger.record!(listener: @listener, scrobble: observation, scope: :scrobble,
          mode: recording ? "resolved" : "inherit", recording:, expected_head: nil,
          reason: recording ? "Confirmed release tracklist suggestion" : "Rejected release tracklist suggestion",
          metadata: { "reason_code" => recording ? "confirmed_candidate" : "rejected_candidate", "comment" => comment,
            "release_batch" => snapshot.except("proposals").merge("positions" => proposal.fetch("positions")),
            "review_snapshot" => ReviewSnapshot.release_batch(snapshot:, ranking:, candidate_mbid: mbid,
              feedback: recording ? "selected" : "rejected", observation_ids: ids) }.compact)
      end
      recording ? observations.size : 0
    end
  end
end
