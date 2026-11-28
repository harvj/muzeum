module CanonicalCatalog
  module TrackComparison
    module_function

    def compare(left, right)
      first, second = left.fetch(:recording), right.fetch(:recording)
      return :equivalent if first["id"] == second["id"]

      shared_isrc = (Array(first["isrcs"]) & Array(second["isrcs"])).any?(&:present?)
      shared_track = left[:track_mbid].present? && left[:track_mbid] == right[:track_mbid]
      versions = [ first, second ].map { |recording| title_key(recording["disambiguation"]) }
      clean_explicit = clean_explicit?(first, second)
      documented_edit = clean_explicit && [ [ first, second ], [ second, first ] ].any? do |source, target|
        Array(source["edit_recording_mbids"]).include?(target["id"])
      end
      companion_edit = clean_explicit && [ [ first, second ], [ second, first ] ].any? do |source, target|
        Array(source["companion_edition_edits"]).any? { |edit| edit["recording_mbid"] == target["id"] }
      end
      corroborated = shared_isrc || shared_track || documented_edit || companion_edit
      caption = caption_key(left[:title])
      matching_remix = caption.end_with?(" remix") && caption == caption_key(right[:title])
      return corroborated ? :uncertain : :different if (titles(left) & titles(right)).empty? && !matching_remix

      # Clean and explicit describe edits. They neither establish nor rule out a shared performance.
      if versions.all?(&:present?) && versions.uniq.many? && !clean_explicit
        return corroborated || matching_remix ? :uncertain : :different
      end

      return :uncertain unless versions.first == versions.last || documented_edit || companion_edit
      # An edition caption can explicitly name the remixer omitted from its structured credits.
      # Older evidence without ISRCs still warrants review, but cannot establish an alias.
      if matching_remix
        return shared_isrc && compatible_edition_remix?(left, right, caption) ? :equivalent : :uncertain
      end

      durations = [ left, right ].map { |slot| slot[:duration_ms] || slot.dig(:recording, "length") }
      length_matches = if documented_edit || companion_edit
        compatible_edit_lengths?(first, second)
      else
        durations.first.to_i.positive? && durations.first == durations.last
      end
      return :uncertain unless length_matches

      left_credits, right_credits = [ left, right ].map { |slot| credits(slot) }
      return :uncertain unless left_credits.present? && left_credits == right_credits

      corroborated ? :equivalent : :uncertain
    end

    def compatible_edition_remix?(left, right, caption)
      slots = [ left, right ]
      recordings = slots.map { |slot| slot.fetch(:recording) }
      lengths = recordings.map { |recording| recording["length"].to_i }
      return false unless lengths.first.positive? && lengths.uniq.one? &&
        slots.all? { |slot| slot[:duration_ms] && (slot[:duration_ms] - lengths.first).abs < 1_000 }
      return false unless recordings.map { |recording| recording["video"] == true }.uniq.size == 1

      recording_credits = recordings.map { |source| credits(recording: source) }
      remixer_names = recording_credits.compact.flat_map { |credit| credit.drop(1).map { |_, name, _| caption_key(name) } }
      remixer = remixer_names.find { |name| caption.end_with?(" #{name} remix") }
      expected = [ caption, (caption.delete_suffix(" #{remixer} remix") + " remix" if remixer) ]
        .compact.map { |name| name.split.sort }
      return false unless recordings.all? { |source| expected.include?(caption_key(source["title"]).split.sort) }

      [ slots.map { |slot| credits(slot) }, recording_credits ].all? do |pair|
        next false unless pair.all?(&:present?) && pair.map { |credit| credit.first.first }.uniq.one?

        shorter, longer = pair.sort_by(&:size).map { |credit| credit.map { |id, name, _| [ id, caption_key(name) ] } }
        missing = longer - shorter
        (shorter - longer).empty? && missing.all? { |_, name| caption.end_with?(" #{name} remix") }
      end
    end

    def caption_key(value)
      title_key(value).gsub(/[^[:alnum:]]+/, " ").strip
    end

    def corroborate_companion_editions(editions)
      editions.group_by { |edition| edition.data.dig("release-group", "id") }.each_value do |group|
        clean, others = group.partition { |edition| title_key(edition.data["disambiguation"]) == "clean" }
        clean.product(others).each do |censored, original|
          next unless censored.data["date"] == original.data["date"] && censored.slots.size == original.slots.size

          pairs = censored.slots.zip(original.slots)
          same_id, edits = pairs.partition { |left, right| left.dig(:recording, "id") == right.dig(:recording, "id") }
          next if same_id.empty? || !edits.all? { |left, right| companion_slots?(left, right) }

          edits.each do |left, right|
            [ [ left, right ], [ right, left ] ].each do |slot, counterpart|
              source = slot.fetch(:recording)
              evidence = { "recording_mbid" => counterpart.dig(:recording, "id"),
                "edition_mbids" => [ censored.data.fetch("id"), original.data.fetch("id") ] }
              slot[:recording] = source.merge("companion_edition_edits" => Array(source["companion_edition_edits"]) | [ evidence ])
            end
          end
        end
      end
      editions
    end

    def companion_slots?(left, right)
      first, second = left.fetch(:recording), right.fetch(:recording)
      clean_explicit?(first, second) && compatible_edit_lengths?(first, second) &&
        (titles(left) & titles(right)).any? && credits(left).present? && credits(left) == credits(right)
    end

    def clean_explicit?(first, second)
      versions = [ first, second ].map { |recording| title_key(recording["disambiguation"]) }.sort
      versions.in?([ %w[clean explicit], [ "clean version edited", "explicit" ] ])
    end

    def compatible_edit_lengths?(first, second)
      lengths = [ first, second ].map { |recording| recording["length"].to_i / 1000 }
      lengths.first.positive? && lengths.first == lengths.last
    end

    def equivalent_sequence?(left, right)
      left.size == right.size && left.zip(right).all? do |first, second|
        first.values_at(:medium, :position) == second.values_at(:medium, :position) && compare(first, second) == :equivalent
      end
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
