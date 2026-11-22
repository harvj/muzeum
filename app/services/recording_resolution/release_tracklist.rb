module RecordingResolution
  class ReleaseTracklist
    MAX_SLOTS = 100

    attr_reader :release, :slots, :revision

    def initialize(release)
      @release = release
      raise ArgumentError unless release.catalog_verified_at? && Clients::Musicbrainz::MBID.match?(release.ingested_from_release_mbid.to_s)

      @slots = release.catalog_track_slots.base_sequence.order(:medium, :position).limit(MAX_SLOTS + 1).includes(recording: :artists).to_a
      raise ArgumentError unless (1..MAX_SLOTS).cover?(slots.size)

      signature = slots.map { |slot| [ slot.medium, slot.position, slot.recording.mbid ] }
      digest = Digest::SHA256.hexdigest(signature.to_json)
      @revision = CatalogRevision.where(entity_type: "Release", entity_id: release.id)
        .where("evidence @> ?", { track_count: slots.size, tracklist_digest: digest }.to_json)
        .where("(evidence->>'edition_mbid' = ? OR evidence @> ?)",
          release.ingested_from_release_mbid, { reviewed_correction: true }.to_json)
        .order(id: :desc).first
      @edition_mbid = revision&.evidence&.fetch("edition_mbid", nil)
      raise ArgumentError unless Clients::Musicbrainz::MBID.match?(@edition_mbid.to_s)
    end

    def evidence
      { "release_id" => release.id, "edition_mbid" => @edition_mbid,
        "revision_id" => revision.id, "tracklist_digest" => revision.evidence.fetch("tracklist_digest"),
        "requests" => revision.evidence["requests"] }.compact
    end

    def assessment_fields
      date = release.attributes.values_at("release_year", "release_month", "release_day").take_while(&:present?)
      { "edition" => { "id" => @edition_mbid, "title" => release.title,
          "date" => date.map { |part| format("%02d", part) }.join("-").presence,
          "country" => release.catalog_country, "complete_tracklist" => true },
        "slots" => slots.map do |slot|
          { "medium" => slot.medium, "position" => slot.position, "number" => slot.number,
            "title" => slot.title, "track_mbid" => slot.track_mbid, "recording_mbid" => slot.recording.mbid,
            "length" => slot.recording.duration_ms }
        end }
    end

    def independently_confirmed(listener, account_id, excluding:)
      ids = slots.reject { |slot| excluding.include?(slot.recording.mbid) }.pluck(:recording_id)
      decisions = Ledger.history(listener).where(user_id: listener.id, actor: "listener", mode: "resolved", recording_id: ids)
        .where.not("evidence ? 'release_batch'").order(id: :desc).limit(20).to_a
      plays = decisions.filter_map { |decision| decision.scrobble_id || decision.evidence["observation_id"] }
      effective = Ledger.effective(listener).where(id: plays, lastfm_account_id: account_id).index_by(&:id)
      decisions.find do |decision|
        play = effective[decision.scrobble_id || decision.evidence["observation_id"]]
        play&.effective_recording_decision_id == decision.id
      end
    end

    def self.candidate(recording, evidence)
      { "id" => recording.mbid, "title" => recording.title, "length" => recording.duration_ms,
        "resolution_candidate_source" => "local_catalog", "local_release_context" => evidence,
        "artist-credit" => recording.artists.map do |artist|
          { "name" => artist.name, "artist" => { "id" => artist.mbid, "name" => artist.name } }
        end }
    end
  end
end
