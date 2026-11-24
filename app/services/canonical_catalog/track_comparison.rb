module CanonicalCatalog
  module TrackComparison
    module_function

    def compare(left, right)
      first, second = left.fetch(:recording), right.fetch(:recording)
      return :equivalent if first["id"] == second["id"]

      shared_isrc = (Array(first["isrcs"]) & Array(second["isrcs"])).any?(&:present?)
      shared_track = left[:track_mbid].present? && left[:track_mbid] == right[:track_mbid]
      corroborated = shared_isrc || shared_track
      return corroborated ? :uncertain : :different if (titles(left) & titles(right)).empty?

      versions = [ first, second ].map { |recording| title_key(recording["disambiguation"]) }
      # Clean and explicit describe edits. They neither establish nor rule out a shared performance.
      if versions.all?(&:present?) && versions.uniq.many? && !versions.all? { |version| version.in?(%w[clean explicit]) }
        return corroborated ? :uncertain : :different
      end

      return :uncertain unless versions.first == versions.last
      durations = [ left, right ].map { |slot| slot[:duration_ms] || slot.dig(:recording, "length") }
      return :uncertain unless durations.first.to_i.positive? && durations.first == durations.last

      left_credits, right_credits = [ left, right ].map { |slot| credits(slot) }
      return :uncertain unless left_credits.present? && left_credits == right_credits

      corroborated ? :equivalent : :uncertain
    end

    def equivalent_sequence?(left, right)
      left.size == right.size && left.zip(right).all? { |first, second| compare(first, second) == :equivalent }
    end

    def titles(slot)
      [ slot[:title], slot.dig(:recording, "title") ].map { |title| title_key(title) }.reject(&:blank?)
    end

    def credits(slot)
      evidence = slot[:source_artist_credit].presence || slot.dig(:recording, "artist-credit")
      credits = Array(evidence).map { |credit| [ credit.dig("artist", "id"), title_key(credit["name"]), credit["joinphrase"].to_s.strip ] }
      credits if credits.all? { |id, name, _| id.present? && name.present? }
    end

    def title_key(value)
      RecordingResolution::DiscoveryTitle.key(value)
    end
  end
end
