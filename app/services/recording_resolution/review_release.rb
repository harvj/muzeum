module RecordingResolution
  class ReviewRelease
    MAX_SLOTS = 100

    def self.project(edition)
      media = Array(edition["media"])
      slots = media.sum { |medium| Array(medium["tracks"]).size }
      complete = slots.positive? && media.all? do |medium|
        medium["tracks"].is_a?(Array) && medium["tracks"].size == medium["track-count"] && !medium["extra-track-layout"]
      end
      state = if slots.zero? && media.none? { |medium| medium["tracks"].is_a?(Array) && medium["track-count"].to_i.positive? }
        "missing"
      elsif complete && slots <= MAX_SLOTS
        "complete"
      else
        "incomplete"
      end
      edition.slice("id", "title", "date", "country", "disambiguation").merge(
        "state" => state, "release_group_mbid" => edition.dig("release-group", "id"), "countries" => Array(edition["release-events"]).flat_map { |event| Array(event["country_codes"]) }.uniq,
        "media" => slots <= MAX_SLOTS ? media.map { |medium| project_medium(medium) } : [])
    end

    def self.project_medium(medium)
      tracks = Array(medium["tracks"]).map do |track|
        track.slice("number", "position", "title").merge("recording_mbid" => track.dig("recording", "id"),
          "length" => track["length"] || track.dig("recording", "length"))
      end
      medium.slice("position", "format").merge("tracks" => tracks)
    end

    def self.from_local(release)
      fields = ReleaseTracklist.new(release).assessment_fields
      fields.fetch("edition").merge("state" => "complete", "media" => grouped_slots(fields["slots"]),
        "provider" => "musicbrainz", "retrieved_at" => release.catalog_verified_at&.utc&.iso8601, "source" => "verified_local_catalog")
    rescue ArgumentError
      nil
    end

    def self.for_assessment(assessment)
      return {} unless assessment

      evidence = assessment.evidence
      retained = evidence.fetch("review_tracklists", {}).dup
      edition = evidence["edition"]
      if edition && edition["id"] && !retained.key?(edition["id"])
        retained[edition["id"]] = edition.merge("state" => edition["complete_tracklist"] ? "complete" : "incomplete",
          "media" => Array(evidence["slots"]).group_by { |slot| slot["medium"] }.map do |position, tracks|
            { "position" => position, "format" => (edition["formats"].first if Array(edition["formats"]).one?), "tracks" => tracks }
          end)
      end
      references = evidence.fetch("discovery_appearances", {}).values.flatten +
        Array(evidence["candidates"]).flat_map do |candidate|
          [ { "id" => candidate.dig("local_release_context", "edition_mbid") }, *Array(candidate["releases"]).first(1) ]
        end
      ids = references.pluck("id").compact.uniq.reject { |id| retained[id]&.fetch("state", nil) == "complete" }.first(3)
      Release.where(ingested_from_release_mbid: ids).where.not(catalog_verified_at: nil).limit(3).each do |release|
        available = from_local(release)
        retained[release.ingested_from_release_mbid] = available if available
      end
      historical = Array(evidence["requests"]).filter_map do |request|
        id = request["endpoint"].to_s.delete_prefix("/ws/2/release/")
        next unless request["provider"] == "musicbrainz" && Clients::Musicbrainz::MBID.match?(id) && !retained.key?(id)

        [ id, request ]
      end.first(3).to_h
      historical.each_key { |id| retained[id] = { "state" => "incomplete" } }
      return retained if historical.empty?

      RequestCache.where("document->'data'->>'id' IN (?)", historical.keys).limit(12).each do |row|
        document = row.document
        id = document.dig("data", "id")
        request = historical.fetch(id)
        next unless request["retrieved_at"].present? && document["retrieved_at"] == request["retrieved_at"]

        digest = Digest::SHA256.hexdigest(document.except("retrieved_at").to_json)
        # JSONB can reorder keys between the initial provider response and a cache read.
        # If the digest differs, require the same retrieval time and a retained checked slot.
        next unless request["projection_digest"] == digest || references.any? { |ref| matching_slot?(ref, document["data"]) }

        retained[id] = project(document.fetch("data"))
      end
      retained
    end

    def self.grouped_slots(slots)
      Array(slots).group_by { |slot| slot["medium"] }.map do |position, tracks|
        { "position" => position, "tracks" => tracks }
      end
    end

    def self.matching_slot?(reference, edition)
      return false unless reference["id"] == edition["id"] && reference["track_mbid"].present?

      Array(edition["media"]).any? do |medium|
        medium["position"] == reference["medium"] && Array(medium["tracks"]).any? do |track|
          track["position"] == reference["position"] && track["id"] == reference["track_mbid"]
        end
      end
    end

    private_class_method :project_medium, :grouped_slots, :matching_slot?
  end
end
