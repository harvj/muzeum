module CanonicalCatalog
  class ReviewedConstruction
    Proposal = Data.define(:construction, :existing)

    def self.for(assessment, recording_mbid)
      editions = Array(assessment&.evidence&.fetch("construction_editions", nil)).filter_map do |data|
        next unless Edition.collection_context?(data)

        Edition.new(data, Store.mbid!(data["id"]))
      rescue Store::Unverified
        nil
      end

      editions.group_by { |edition| edition.data.dig("release-group", "id") }.filter_map do |group, evidence|
        construction = Construction.new(evidence)
        next unless (construction.base.slots + construction.additional_slots).any? { |slot| slot.dig(:recording, "id") == recording_mbid }

        existing = Release.where(release_group_mbid: group).limit(2).to_a
        next if existing.many?

        Proposal.new(construction, existing.first)
      rescue Store::Unverified
        nil
      end
    end

    def self.needs_review?(proposal, recording)
      release = proposal.existing
      return true unless release&.catalog_verified_at

      base = proposal.construction.base
      date = [ release.release_year, release.release_month, release.release_day ].compact.map { |part| part.to_s.rjust(2, "0") }.join("-")
      return true if date != base.data["date"]

      expected = base.slots.map { |slot| [ slot[:medium], slot[:position], slot.dig(:recording, "id") ] }
      actual = release.catalog_track_slots.base_sequence.order(:medium, :position).joins(:recording).pluck(:medium, :position, "recordings.mbid")
      return true if actual != expected

      edition_ids = proposal.construction.appearances.pluck("id")
      actual_additions = release.catalog_track_slots.additional_appearances.where(edition_mbid: edition_ids)
        .joins(:recording).pluck(:edition_mbid, :appearance_date, :medium, :position, "recordings.mbid")
      expected_additions = proposal.construction.additional_slots.map do |slot|
        [ *slot.values_at(:edition_mbid, :appearance_date, :medium, :position), slot.dig(:recording, "id") ]
      end
      actual_additions.sort != expected_additions.sort || recording.nil? || !release.catalog_track_slots.exists?(recording_id: recording.id)
    end

    def self.head(release)
      return unless release

      fields = release.attributes.values_at("id", "release_year", "release_month", "release_day", "catalog_verified_at")
      slots = release.catalog_track_slots.order(:id).pluck(:id, :recording_id, :title, :edition_mbid, :appearance_date, :medium, :position)
      Digest::SHA256.hexdigest([ fields, slots ].to_json)
    end

    def self.apply!(proposal, request, assessment, corrected_release: nil)
      construction = proposal.construction
      provenance = Struct.new(:provenance).new(Array(assessment.evidence["requests"]))
      Store.new(request, provenance).release(construction.base.data, construction.base.slots,
        strict_collection: true, checked_editions: construction.appearances,
        additional_slots: construction.additional_slots, corrected_release:)
    end
  end
end
