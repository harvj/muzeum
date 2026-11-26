module RecordingResolution
  class RecordingProvenance
    EDITION_LOOKUPS = 16
    RELATED_LOOKUPS = 6
    VERSION_RELATIONS = /\A(?:remix|edit|instrumental|remaster|live performance|alternate version|alternate take|karaoke|dub)\z/i

    def initialize(client, session)
      @client, @session = client, session
    end

    def call(mbid, retained:, counterparts:)
      gaps = []
      recording = checked_recording(mbid, gaps)
      appearances = []
      browse_complete = false
      if recording
        begin
          appearances = @client.provenance_releases(@session, mbid) { |page| appearances = page }
          browse_complete = true
        rescue CanonicalCatalog::Store::Unverified, ProviderError => error
          raise if error.is_a?(ProviderError) && error.deferred

          gaps << "MusicBrainz release browse incomplete: #{error.message}"
        end
      end
      references = (appearances + Array(recording&.fetch("releases", nil))).uniq { |row| row["id"] }
      known = retained.index_by { |data| data["id"] }
      retained_references = retained.filter_map do |data|
        includes_recording = Array(data["media"]).any? do |medium|
          Array(medium["tracks"]).any? { |track| track.dig("recording", "id") == mbid }
        end
        data.except("media") if includes_recording
      end
      references = (references + retained_references).uniq { |row| row["id"] }
      if browse_complete && references.any? { |row| appearances.none? { |appearance| appearance["id"] == row["id"] } }
        gaps << "Retained appearances disagree with the current release browse."
      end
      lookups = 0
      releases = references.map do |row|
        data = known[row["id"]]
        if data.nil? && lookups < EDITION_LOOKUPS
          lookups += 1
          data = @client.edition(@session, row["id"], catalog: true)
        end
        appearance(row, data, mbid)
      rescue CanonicalCatalog::Store::Unverified, ProviderError => error
        raise if error.is_a?(ProviderError) && error.deferred

        row
      end
      gaps << "One or more exact track positions could not be verified within the edition budget." if releases.any? { |row| row["slots"].blank? }

      related_ids = Array(recording&.fetch("relationships", nil)).filter_map do |relation|
        relation.dig("target", "id") if relation["target_type"] == "recording" && VERSION_RELATIONS.match?(relation["type"].to_s)
      end
      ids = (counterparts | related_ids) - [ mbid ]
      gaps << "Some related recordings exceeded the lookup budget." if ids.size > RELATED_LOOKUPS
      related = ids.first(RELATED_LOOKUPS).filter_map { |id| checked_recording(id, gaps) }
      dated = releases.select { |row| row["slots"].present? && row["status"].in?(%w[Official Withdrawn]) && publication_date?(row["date"]) }
      earliest = dated.reject { |row| dated.any? { |other| other["date"].start_with?("#{row['date']}-") } }
        .min_by { |row| row.values_at("date", "id") }

      { "checked_at" => Time.current.utc.iso8601, "exact_recording" => recording, "releases" => releases,
        "related_recordings" => related, "counterpart_mbids" => counterparts, "browse_complete" => browse_complete,
        "incomplete" => gaps.any?, "limitations" => gaps, "earliest_publication" => earliest&.slice("id", "title", "date"),
        "classification" => classification(recording, related, counterparts) }.compact
    end

    private

    def checked_recording(id, gaps)
      data = @client.provenance_recording(@session, id)
      return data if data && data["id"] == id

      gaps << "Exact recording #{id} could not be verified."
      nil
    rescue ProviderError => error
      raise if error.deferred

      gaps << "Recording #{id}: #{error.message}"
      nil
    end

    def appearance(row, data, mbid)
      return row unless data

      edition = CanonicalCatalog::Edition.new(data, row.fetch("id"), recording_mbid: mbid)
      slots = edition.slots.select { |slot| slot[:source_recording_mbid] == mbid }.map do |slot|
        slot.slice(:medium, :position, :number, :title, :track_mbid, :duration_ms, :source_artist_credit).stringify_keys
      end
      signature = edition.slots.pluck(:source_recording_mbid)
      row.merge(data.slice("date", "country", "status", "artist-credit", "edition_relationships"),
        "media" => Array(data["media"]).map { |medium| medium.slice("position", "format", "track-count") },
        "slots" => slots, "sequence_digest" => Digest::SHA256.hexdigest(signature.to_json))
    end

    def classification(recording, related, counterparts)
      return "unclassified" unless recording

      base = related.select { |item| counterparts.include?(item["id"]) }
      return "alternate" if base.any? do |item|
        version_link?(recording, item["id"]) || version_link?(item, recording["id"]) ||
          ((performance_works(recording) & performance_works(item)).any? &&
            (marked_version?(recording) || documented_event?(recording)))
      end
      return "independent" if counterparts.empty? && documented_event?(recording)

      "unclassified"
    end

    def performance_works(recording)
      Array(recording["relationships"]).filter_map do |relation|
        relation.dig("target", "id") if relation["target_type"] == "work" && relation["type"] == "performance"
      end
    end

    def marked_version?(recording)
      Array(recording["relationships"]).any? do |relation|
        relation["type"] == "performance" && (Array(relation["attributes"]) & %w[instrumental live]).any?
      end
    end

    def documented_event?(recording)
      relationships = Array(recording["relationships"])
      relationships.any? do |performance|
        date = performance["begin"]
        performance["target_type"] == "work" && performance["type"] == "performance" && date.to_s.length == 10 &&
          relationships.any? do |place|
            place["target_type"] == "place" && place["begin"] == date && place["type"].in?([ "recorded at", "video shot at" ])
          end
      end
    end

    def version_link?(recording, target)
      Array(recording["relationships"]).any? do |relation|
        relation["target_type"] == "recording" && relation.dig("target", "id") == target &&
          VERSION_RELATIONS.match?(relation["type"].to_s)
      end
    end

    def publication_date?(value)
      return false unless value.to_s.match?(/\A\d{4}(?:-\d{2}){0,2}\z/)

      Date.new(*value.split("-").map(&:to_i))
      true
    rescue Date::Error
      false
    end
  end
end
