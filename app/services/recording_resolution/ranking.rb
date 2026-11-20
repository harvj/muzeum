module RecordingResolution
  class Ranking
    VERSION = "recording-ranking-v1"
    VERSION_MARKERS = /\b(live|remix|acoustic|demo|alternate|edit|instrumental|remaster)(?:ed)?\b/i

    def self.call(surface, evidence)
      Workspace.candidate_evidence(evidence).filter_map do |candidate|
        new(surface, evidence, candidate).evaluate
      end.sort_by { |row| [ -row.fetch("score"), row.fetch("recording_mbid") ] }
    end

    def self.recommended?(ranks)
      first, second = ranks
      first && (!second || first["score"] > second["score"]) &&
        first.fetch("inputs").values.none? { |item| item["state"] == "contradictory" } &&
        %w[recording_identifier edition_slot].any? { |key| first.dig("inputs", key, "state") == "positive" }
    end

    def initialize(surface, evidence, candidate)
      @surface, @evidence, @candidate = surface, evidence, candidate
      @inputs = {}
    end

    def evaluate
      claims = @evidence.fetch("source_claims", {})
      id = @candidate.fetch("id")
      credits = Array(@candidate["artist-credit"])
      names = credits.flat_map { |credit| [ credit["name"], credit.dig("artist", "name") ] }.compact
      names << credits.map { |credit| "#{credit['name']}#{credit['joinphrase']}" }.join if credits.any?
      artist_ids = credits.filter_map { |credit| credit.dig("artist", "id") }
      expected_id = (@evidence.dig("verification", "redirected_to") || claims["track_mbid"]).to_s
      verified = expected_id.present? && id.casecmp?(expected_id) &&
        (@evidence.dig("verified_recording", "id") == id || @candidate["verified_local_claim"] == true)

      factor("recording_identifier", verified ? true : nil, 8, 0, "Verified source recording identifier", nil)
      claimed_other = @evidence.dig("verified_recording", "id") == expected_id && expected_id.present? && !id.casecmp?(expected_id)
      factor("different_verified_recording", claimed_other ? false : nil, 0, -6, nil, "The source recording identifier resolves to a different recording")
      factor("title", comparable(@surface.track, @candidate["title"]), 2, -3,
        "Recording title matches after text normalization", "Recording title differs")
      factor("artist_name", names.empty? || @surface.artist.blank? ? nil : names.any? { |name| comparable(@surface.artist, name) },
        2, -3, "Artist name or credited name matches", "Artist credit differs")
      artist_id = claims["artist_mbid"]
      factor("artist_identifier", !Clients::Musicbrainz::MBID.match?(artist_id.to_s) || artist_ids.empty? ? nil : artist_ids.any? { |other| artist_id.casecmp?(other) },
        3, -4, "The source artist identifier matches a credited artist", "The source artist identifier differs from the credited artists")
      slot = @evidence.dig("edition", "title").present? && @evidence.dig("edition", "title") == @surface.album &&
        Array(@evidence["slots"]).any? { |entry| entry["recording_mbid"] == id && entry["title"] == @surface.track }
      factor("edition_slot", slot ? true : nil, 4, 0, "A checked MusicBrainz edition contains this track slot", nil)

      observed_versions = versions(@surface.track)
      candidate_versions = versions([ @candidate["title"], @candidate["disambiguation"] ].join(" "))
      version_match = if observed_versions.any? && candidate_versions.any?
        observed_versions == candidate_versions
      elsif candidate_versions.any? || @candidate["video"] == true
        false
      end
      factor("version", version_match, 2, -4, "Version markers agree", "Catalog marks a distinct or video version that the source does not confirm")
      factor("duration", nil, 0, 0, nil, nil)
      manual = @evidence["manually_verified_mbid"] == id
      factor("manual_lookup", manual ? true : nil, 0, 0, "MusicBrainz verified the manually entered identifier", nil)

      # Text narrows discovery. A text-only candidate is still a choice for human review.
      return unless verified || slot || manual || (@inputs["title"]["state"] == "positive" &&
        %w[artist_name artist_identifier].any? { |key| @inputs[key]["state"] == "positive" })

      {
        "recording_mbid" => id, "score" => @inputs.values.sum { |factor| factor.fetch("weight") },
        "version" => VERSION, "inputs" => @inputs,
        "provenance" => @candidate.fetch("resolution_candidate_source", "musicbrainz"),
        "source" => { "artist" => @surface.artist, "track" => @surface.track,
          "album" => @surface.album, "claims" => claims },
        "catalog" => @candidate.slice("title", "artist-credit", "length", "disambiguation", "video")
      }
    end

    private

    def factor(key, match, positive, negative, support, conflict)
      @inputs[key] = case match
      when true then { "state" => "positive", "weight" => positive, "explanation" => support }
      when false then { "state" => "contradictory", "weight" => negative, "explanation" => conflict }
      else { "state" => "unavailable", "weight" => 0 }
      end
    end

    def comparable(first, second)
      return if first.blank? || second.blank?

      first.unicode_normalize.downcase.squish == second.unicode_normalize.downcase.squish
    end

    def versions(text)
      text.to_s.scan(VERSION_MARKERS).flatten.map(&:downcase).uniq.sort
    end
  end
end
