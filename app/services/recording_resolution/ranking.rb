module RecordingResolution
  class Ranking
    VERSION = "recording-ranking-v1"
    VERSION_MARKERS = /\b(live|remix|acoustic|demo|alternate|edit|instrumental|remaster)(?:ed)?\b/i

    def self.call(surface, evidence, discovery: true, caption_bonus: false)
      Workspace.candidate_evidence(evidence).filter_map do |candidate|
        new(surface, evidence, candidate, discovery:, caption_bonus:).evaluate
      end.sort_by { |row| [ -row.fetch("score"), row.fetch("recording_mbid") ] }
    end

    def self.recommended?(ranks)
      first, second = ranks
      if first&.dig("inputs", "recording_identifier", "state") == "positive" &&
          ranks.drop(1).any? { |rank| rank.dig("inputs", "catalog_release_appearance", "provenance", "relationship") == "matching_catalog_caption" }
        return false
      end
      first && (!second || first["score"] > second["score"]) &&
        first.fetch("inputs").values.none? { |item| item["state"] == "contradictory" } &&
        %w[recording_identifier edition_slot].any? { |key| first.dig("inputs", key, "state") == "positive" }
    end

    def initialize(surface, evidence, candidate, discovery:, caption_bonus:)
      @surface, @evidence, @candidate = surface, evidence, candidate
      @inputs = {}
      @discovery = discovery
      @caption_bonus = caption_bonus
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
      context = @candidate["local_release_context"]
      independent_release_support = context && context["independent_decision_id"]
      if independent_release_support
        factor("local_release_history", true, 2, 0,
          "This stored release contains another recording independently confirmed in your archive", nil)
        @inputs.fetch("local_release_history")["provenance"] = context
      end
      appearance = @candidate["release_discovery"] unless slot
      if appearance
        weight = @caption_bonus && appearance["relationship"] == "matching_catalog_caption" ? 2 : 1
        factor("catalog_release_appearance", true, weight, 0,
          "MusicBrainz lists this recording in the checked catalog tracklist", nil)
        @inputs.fetch("catalog_release_appearance")["provenance"] = appearance
      end

      # Text narrows discovery. A text-only candidate is still a choice for human review.
      return unless verified || slot || manual || appearance || (@inputs["title"]["state"] == "positive" &&
        %w[artist_name artist_identifier].any? { |key| @inputs[key]["state"] == "positive" })

      {
        "recording_mbid" => id, "score" => @inputs.values.sum { |factor| factor.fetch("weight") },
        "version" => version(independent_release_support, appearance), "inputs" => @inputs,
        "provenance" => @candidate.fetch("resolution_candidate_source", "musicbrainz"),
        "source" => { "artist" => @surface.artist, "track" => @surface.track,
          "album" => @surface.album, "claims" => claims },
        "catalog" => @candidate.slice("title", "artist-credit", "length", "disambiguation", "video")
      }.tap { |result| result["local_release_context"] = context if context }
    end

    private

    def version(independent_release_support, appearance)
      return "recording-ranking-v1-release-discovery-v2" if appearance && !@caption_bonus
      return "recording-ranking-v1-release-discovery-v1" if appearance || @typographic_match
      return "recording-ranking-v1-local-release-v1" if independent_release_support

      VERSION
    end

    def factor(key, match, positive, negative, support, conflict)
      @inputs[key] = case match
      when true then { "state" => "positive", "weight" => positive, "explanation" => support }
      when false then { "state" => "contradictory", "weight" => negative, "explanation" => conflict }
      else { "state" => "unavailable", "weight" => 0 }
      end
    end

    def comparable(first, second)
      return if first.blank? || second.blank?

      previous = first.unicode_normalize.downcase.squish == second.unicode_normalize.downcase.squish
      return previous unless @discovery

      match = DiscoveryTitle.match?(first, second)
      @typographic_match ||= match && !previous
      match
    end

    def versions(text)
      text.to_s.scan(VERSION_MARKERS).flatten.map(&:downcase).uniq.sort
    end
  end
end
