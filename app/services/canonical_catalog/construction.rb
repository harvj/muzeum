module CanonicalCatalog
  class Construction
    attr_reader :base, :appearances, :additional_slots

    def initialize(editions)
      editions = editions.select { |edition| Edition.collection_context?(edition.data) }
      original = editions.select { |edition| Edition.original_context?(edition.data) }
      raise Store::Unverified, "The original tracklist remains unverified" if original.empty?

      by_sequence = original.group_by { |edition| signature(edition) }
      sequence = by_sequence.keys.min_by(&:length)
      if by_sequence.keys.any? { |other| other.first(sequence.length) != sequence }
        raise Store::Unverified, "Original tracklists disagree on order or membership"
      end

      @base = by_sequence.fetch(sequence).min_by { |edition| edition.data.fetch("id") }
      original_date = base.data.fetch("date")
      @additional_slots = []
      base_recordings = sequence.map(&:last).to_set
      @appearances = editions.filter_map do |edition|
        date = edition.data["date"]
        next unless date.present? && date >= original_date

        additions = edition.slots.reject { |slot| base_recordings.include?(slot.dig(:recording, "id")) }
        @additional_slots.concat(additions.map { |slot| slot.merge(edition_mbid: edition.data.fetch("id"), appearance_date: date) })
        edition.data.slice("id", "title", "date", "genres", "tags").merge(
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

    private

    def signature(edition)
      edition.slots.map { |slot| [ slot.fetch(:medium), slot.fetch(:position), slot.dig(:recording, "id") ] }
    end
  end
end
