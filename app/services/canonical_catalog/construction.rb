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

      by_sequence = originals.group_by { |edition| sequence(edition) }
      # A complete launch-day edition with an appended bonus sequence is
      # evidence of appearances. The shorter independently verified edition is the base.
      bases = by_sequence.reject do |tracks, _|
        by_sequence.keys.any? { |other| other.length < tracks.length && tracks.first(other.length) == other }
      end
      bases.values.map do |equivalent|
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
      base_recordings = self.class.sequence(@base).to_set
      competing_sequences = originals.excluding(@base).map { |edition| self.class.sequence(edition) }.to_set
      @appearances = editions.filter_map do |edition|
        date = edition.data["date"]
        next unless date.present? && date >= original_date

        # Competing original sequences are kept in the evidence without admitting their tracks.
        additions = if competing_sequences.include?(self.class.sequence(edition))
          []
        else
          edition.slots.select do |slot|
            id = slot.dig(:recording, "id")
            !base_recordings.include?(id) && (recording_mbid.nil? || id == recording_mbid)
          end
        end
        @additional_slots.concat(additions.map { |slot| slot.merge(edition_mbid: edition.data.fetch("id"), appearance_date: date) })
        edition.data.slice("id", "title", "date", "country", "status", "packaging", "disambiguation", "edition_relationships", "genres", "tags").merge(
          "track_count" => edition.slots.size,
          "additional_tracks" => additions.map do |slot|
            { "recording_mbid" => slot.dig(:recording, "id"), "title" => slot.fetch(:title),
              "medium" => slot.fetch(:medium), "position" => slot.fetch(:position),
              "edition_appearance_date" => date,
              "provider_first_release_date" => slot.dig(:recording, "first-release-date") }.compact
          end
        )
      end.sort_by { |appearance| appearance.values_at("date", "id") }
    end
  end
end
