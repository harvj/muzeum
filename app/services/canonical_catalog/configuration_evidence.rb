module CanonicalCatalog
  module ConfigurationEvidence
    module_function

    # Provider editions stay separate; this key identifies the musical program
    # shown in Resolution. Source track IDs, dates and places are provenance.
    def key(edition)
      [ edition.data.dig("release-group", "id"), mix(edition),
        edition.slots.map { |slot| slot.values_at(:medium, :position, :source_recording_mbid) } ]
    end

    def mix(edition)
      label = edition.data["disambiguation"].to_s
      return "Dolby Atmos" if label.match?(/\b(?:dolby\s+)?atmos\b/i)
      return "Surround mix" if label.match?(/\b(?:surround|[57]\.1)\b/i)
      return "Mono" if label.match?(/\bmono\b/i)
      return "Stereo" if label.match?(/\bstereo\b/i)

      label.strip.presence if label.match?(/\b(?:mix(?:es)?|remix(?:es)?)\b/i)
    end
  end
end
