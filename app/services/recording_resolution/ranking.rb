module RecordingResolution
  class Ranking
    VERSION = "recording-ranking-v1"
    SOURCE_HINTS_VERSION = "recording-ranking-v2-source-hints"
    VERSION_MARKERS = /\b(live|remix|acoustic|demo|alternate|edit|instrumental|remaster)(?:ed)?\b/i

    def self.call(surface, evidence, discovery: true, caption_bonus: false, source_hints: false)
      candidates = source_hints ? evidence.except("verified_recording") : evidence
      Workspace.candidate_evidence(candidates).filter_map do |candidate|
        new(surface, evidence, candidate, discovery:, caption_bonus:, source_hints:).evaluate
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

    def initialize(surface, evidence, candidate, discovery:, caption_bonus:, source_hints:)
      @surface, @evidence, @candidate = surface, evidence, candidate
      @inputs = {}
      @discovery = discovery
      @caption_bonus = caption_bonus
      @source_hints = source_hints
    end

    def evaluate
      source_claims = @evidence.fetch("source_claims", {})
      claims = @source_hints ? {} : source_claims
      id = @candidate.fetch("id")
      credits = Array(@candidate["artist-credit"])
      names = credits.flat_map { |credit| [ credit["name"], credit.dig("artist", "name") ] }.compact
      names << credits.map { |credit| "#{credit['name']}#{credit['joinphrase']}" }.join if credits.any?
      artist_ids = credits.filter_map { |credit| credit.dig("artist", "id") }
      expected_id = (@evidence.dig("verification", "redirected_to") || claims["track_mbid"]).to_s unless @source_hints
      expected_id = expected_id.to_s
      verified = expected_id.present? && id.casecmp?(expected_id) &&
        (@evidence.dig("verified_recording", "id") == id || @candidate["verified_local_claim"] == true)

      factor("recording_identifier", verified ? true : nil, 8, 0, "Verified source recording identifier", nil)
      claimed_other = @evidence.dig("verified_recording", "id") == expected_id && expected_id.present? && !id.casecmp?(expected_id)
      factor("different_verified_recording", claimed_other ? false : nil, 0, -6, nil, "The source recording identifier resolves to a different recording")
      catalog_artist = @evidence["canonical_artist_mbid"] if @source_hints
      primary = credits.first || {}
      primary_match = (catalog_artist.present? && primary.dig("artist", "id") == catalog_artist) ||
        [ primary["name"], primary.dig("artist", "name") ].any? { |name| comparable(@surface.artist, name) }
      title_match = comparable(@surface.track, @candidate["title"])
      if @candidate["adaptive_search"] && !title_match && primary_match
        observed_title = DiscoveryTitle.credit_key(@surface.track)
        title_match = observed_title.present? && observed_title == DiscoveryTitle.credit_key(@candidate["title"])
      end
      credited_title = @discovery && !title_match && primary_match && DiscoveryTitle.recording_match?(@surface.track, @candidate["title"], credits)
      interpretation = @discovery && @evidence["title_interpretation"]
      interpreted_title = !!interpretation && primary_match &&
        TitleInterpretation.recording_title_match?(interpretation, @candidate["title"])
      slot_title = @candidate.dig("release_discovery", "track_title") if @discovery
      numbered_caption = !title_match && primary_match && DiscoveryTitle.match?(@surface.track, slot_title) &&
        DiscoveryTitle.match?(slot_title.to_s.split(":", 2).second, @candidate["title"])
      title_explanation = if numbered_caption
        "The checked track caption matches; the recording title omits its section prefix"
      elsif interpreted_title && !title_match
        "Recording matches the interpreted title; check the version and release evidence"
      elsif credited_title
        "Recording title and featured artist credit match"
      else
        "Recording title matches after text normalization"
      end
      factor("title", credited_title || title_match || numbered_caption || interpreted_title, 2, -3, title_explanation, "Recording title differs")
      catalog_match = catalog_artist.present? && artist_ids.include?(catalog_artist)
      artist_match = catalog_match || names.any? { |name| comparable(@surface.artist, name) } unless names.empty? || @surface.artist.blank?
      factor("artist_name", catalog_match ? true : artist_match, 2, -3,
        catalog_match ? "Verified Muzeum artist identity matches a credited artist" : "Artist name or credited name matches",
        "Artist credit differs")
      artist_id = claims["artist_mbid"]
      factor("artist_identifier", !Clients::Musicbrainz::MBID.match?(artist_id.to_s) || artist_ids.empty? ? nil : artist_ids.any? { |other| artist_id.casecmp?(other) },
        3, -4, "The source artist identifier matches a credited artist", "The source artist identifier differs from the credited artists")
      slot = @evidence.dig("edition", "title").present? && @evidence.dig("edition", "title") == @surface.album &&
        Array(@evidence["slots"]).any? do |entry|
          entry["recording_mbid"] == id && (entry["title"] == @surface.track ||
            credited_title && DiscoveryTitle.recording_match?(@surface.track, entry["title"], credits))
        end
      factor("edition_slot", slot ? true : nil, 4, 0, "A checked MusicBrainz edition contains this track slot", nil)

      observed_versions = versions(credited_title ? DiscoveryTitle.featured_credit(@surface.track).first : @surface.track)
      candidate_versions = versions([ @candidate["title"], @candidate["disambiguation"] ].join(" "))
      version_match = if observed_versions.any? && candidate_versions.any?
        observed_versions == candidate_versions
      elsif candidate_versions.any? || @candidate["video"] == true
        false
      end
      if interpretation
        observed_versions = musical_versions(interpretation)
        candidate_descriptors = Array(TitleInterpretation.call(@candidate["title"])&.fetch("descriptors"))
        candidate_descriptors << TitleInterpretation.descriptor(@candidate["disambiguation"].to_s)
        candidate_versions = candidate_descriptors.compact.select { |item| item["kind"] == "version" }
        version_match = structured_version_match(interpretation, observed_versions, candidate_versions)
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
      unless slot || appearance
        reference = Array(@candidate["releases"]).first
        tracklist = @evidence.dig("review_tracklists", reference["id"]) if reference
        if tracklist && Array(tracklist["media"]).any? { |disc| Array(disc["tracks"]).any? { |track| track["recording_mbid"] == id } }
          appearance = reference.merge("relationship" => "verified_catalog_tracklist")
        end
      end
      if appearance
        weight = @caption_bonus && appearance["relationship"] == "matching_catalog_caption" ? 2 : 1
        factor("catalog_release_appearance", true, weight, 0,
          "MusicBrainz lists this recording in the checked catalog tracklist", nil)
        @inputs.fetch("catalog_release_appearance")["provenance"] = appearance
      end

      # Text narrows discovery. A text-only candidate is still a choice for human review.
      adaptive = @candidate["adaptive_search"]
      if adaptive
        factor("adaptive_search", true, 0, 0, "Found through a broader search; verify the title qualifier and version before confirming", nil)
        @inputs.fetch("adaptive_search")["provenance"] = adaptive
      end
      return unless verified || slot || manual || appearance || adaptive || (@inputs["title"]["state"] == "positive" &&
        %w[artist_name artist_identifier].any? { |key| @inputs[key]["state"] == "positive" })

      {
        "recording_mbid" => id, "score" => @inputs.values.sum { |factor| factor.fetch("weight") },
        "version" => version(independent_release_support, appearance), "inputs" => @inputs,
        "provenance" => @candidate.fetch("resolution_candidate_source", "musicbrainz"),
        "source" => { "artist" => @surface.artist, "track" => @surface.track,
          "album" => @surface.album, "claims" => source_claims },
        "catalog" => @candidate.slice("title", "artist-credit", "length", "disambiguation", "video")
      }.tap { |result| result["local_release_context"] = context if context }
    end

    private

    def version(independent_release_support, appearance)
      return "recording-ranking-v3-structured-title" if @discovery && @evidence["title_interpretation"]
      return SOURCE_HINTS_VERSION if @source_hints
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

    def musical_versions(interpretation)
      Array(interpretation&.fetch("descriptors")).select { |item| item["kind"] == "version" }.pluck("name").uniq
    end

    def structured_version_match(interpretation, observed, candidate)
      candidate_names = candidate.pluck("name").uniq
      return false if @candidate["video"] == true || (candidate_names - observed).any?
      return if observed.empty? || (observed - candidate_names).any?

      # Matching types alone cannot establish a particular concert, remix or take.
      qualified = interpretation.fetch("descriptors").select { |item| item["kind"] == "version" && item["text"].downcase != item["name"] }
      return if qualified.any? { |item| candidate.none? { |other| DiscoveryTitle.match?(item["text"], other["text"]) } }

      true
    end

    def versions(text)
      text.to_s.scan(VERSION_MARKERS).flatten.map(&:downcase).uniq.sort
    end
  end
end
