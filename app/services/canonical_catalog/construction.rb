module CanonicalCatalog
  class Construction
    attr_reader :base, :appearances, :additional_slots

    EDITION_VARIANT = /\b(?:deluxe|expanded|bonus|reissue|remaster(?:ed)?|anniversary)\b/i

    def self.originals(editions)
      originals = editions.select do |edition|
        data = edition.data
        title_variant = data["title"].to_s != RecordingResolution::DiscoveryTitle.album_base(data["title"])
        Edition.original_context?(data) && !title_variant && !data["disambiguation"].to_s.match?(EDITION_VARIANT)
      end

      groups = originals.sort_by { |edition| edition.data.fetch("id") }.each_with_object([]) do |edition, grouped|
        equivalent = grouped.find do |group|
          group.all? { |other| TrackComparison.equivalent_sequence?(edition.slots, other.slots) }
        end
        equivalent ? equivalent << edition : grouped << [ edition ]
      end
      # An independently verified launch sequence can identify an appended program.
      # An uncertain MBID match does not establish that prefix.
      bases = groups.reject do |group|
        tracks = group.first.slots
        groups.any? do |other|
          shorter = other.first.slots
          shorter.size < tracks.size && group.all? do |edition|
            other.all? { |base| TrackComparison.equivalent_sequence?(edition.slots.take(shorter.size), base.slots) }
          end
        end
      end
      bases.map do |equivalent|
        equivalent.min_by do |edition|
          data = edition.data
          origin = Array(data["artist-credit"]).filter_map { |credit| credit.dig("artist", "country").presence }.uniq
          [ origin.one? && data["country"] == origin.first ? 0 : 1,
            data["country"].blank? || data["country"] == "XW" ? 1 : 0,
            Array(data["media"]).any? { |medium| medium["format"].present? } ? 0 : 1,
            data["packaging"].presence.in?([ nil, "None", "Unknown" ]) ? 1 : 0,
            data.fetch("id") ]
        end
      end.sort_by { |edition| edition.data.fetch("id") }
    end

    def self.sequence(edition)
      edition.slots.map { |slot| slot.dig(:recording, "id") }
    end

    def initialize(editions, base: nil, recording_mbid: nil)
      editions = editions.select { |edition| Edition.collection_context?(edition.data) }
      originals = self.class.originals(editions)
      raise Store::Unverified, "The original tracklist remains unverified" if originals.empty?
      if base ? !originals.include?(base) : originals.many?
        raise Store::Unverified, "Original tracklists disagree on order or membership"
      end

      @base = base || originals.first
      original_date = @base.data.fetch("date")
      @additional_slots = []
      competing = originals.excluding(@base)
      base_recordings = self.class.sequence(@base).to_set
      @appearances = editions.filter_map do |edition|
        date = edition.data["date"]
        next unless date.present? && date >= original_date

        # A competing original program is evidence in its own right.
        conflicts = competing.any? { |other| TrackComparison.equivalent_sequence?(edition.slots, other.slots) }
        additions, uncertain = [], []
        edition.slots.each do |slot|
          next if base_recordings.include?(slot.dig(:recording, "id"))

          comparisons = @base.slots.map { |base_slot| TrackComparison.compare(slot, base_slot) }
          if comparisons.all? { |result| result == :different }
            additions << slot
          elsif !comparisons.include?(:equivalent)
            uncertain << slot
          end
        end
        admitted = conflicts ? [] : additions
        admitted = admitted.select { |slot| slot.dig(:recording, "id") == recording_mbid } if recording_mbid
        @additional_slots.concat(admitted.map { |slot| slot.merge(edition_mbid: edition.data.fetch("id"), appearance_date: date) })
        edition.data.slice("id", "title", "date", "country", "status", "packaging", "disambiguation", "edition_relationships", "genres", "tags").merge(
          "track_count" => edition.slots.size,
          "uncertain_tracks" => uncertain.map { |slot| slot_evidence(slot, date) },
          "additional_tracks" => conflicts ? [] : additions.map { |slot| slot_evidence(slot, date) },
          "competing_sequence_tracks" => conflicts ? additions.map { |slot| slot_evidence(slot, date) } : []
        )
      end.sort_by { |appearance| appearance.values_at("date", "id") }
    end

    private

    def slot_evidence(slot, date)
      { "recording_mbid" => slot.dig(:recording, "id"), "track_mbid" => slot.fetch(:track_mbid), "title" => slot.fetch(:title),
        "medium" => slot.fetch(:medium), "position" => slot.fetch(:position),
        "edition_appearance_date" => date, "version" => slot.dig(:recording, "disambiguation").presence,
        "provider_first_release_date" => slot.dig(:recording, "first-release-date") }.compact
    end
  end
end
