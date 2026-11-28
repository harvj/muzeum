module CanonicalCatalog
  class ReviewedConstruction
    Proposal = Data.define(:construction, :existing)

    def self.for(assessment, recording_mbid, source_ids: [ recording_mbid ])
      history = assessment&.evidence&.fetch("recording_publications", nil)
      compilations = source_ids.filter_map { |id| history&.dig(id, "first_publication_compilation_group") }.to_set
      editions = Array(assessment&.evidence&.fetch("construction_editions", nil)).filter_map do |data|
        next if Edition.mispressing?(data)
        next unless Edition.collection_context?(data, compilation: compilations.include?(data.dig("release-group", "id")))

        Edition.new(data, Store.mbid!(data["id"]))
      rescue Store::Unverified
        nil
      end

      editions.group_by { |edition| edition.data.dig("release-group", "id") }.flat_map do |group, evidence|
        if history
          next [] unless source_ids.any? { |id| Array(history.dig(id, "original_groups")).include?(group) }
        elsif group == assessment.evidence["pending_original_group"]
          next []
        end
        next [] unless evidence.any? { |edition| edition.slots.any? { |slot| source_ids.include?(slot.dig(:recording, "id")) } }

        existing = Release.where(release_group_mbid: group).limit(2).to_a
        next [] if existing.many?

        compilation = compilations.include?(group)
        Construction.selectable_bases(evidence, compilation:).filter_map do |base|
          construction = Construction.new(evidence, base:, recording_mbid: source_ids, compilation:)
          if (base.slots + construction.additional_slots).any? { |slot| source_ids.include?(slot.dig(:recording, "id")) }
            Proposal.new(construction, existing.first)
          end
        end
      rescue Store::Unverified
        []
      end
    end

    def self.resolution_choices(assessment, recording_mbid, recording, source_ids: [ recording_mbid ])
      admitted = recording.admitted_releases.where.not(catalog_verified_at: nil) if recording
      choices = self.for(assessment, recording_mbid, source_ids:)
      if admitted&.exists?
        choices.select! { |proposal| proposal.existing && admitted.exists?(id: proposal.existing.id) }
      end
      choices.group_by { |proposal| proposal.construction.base.data.dig("release-group", "id") }.values
        .reject { |group| group.any? { |proposal| !needs_review?(proposal, recording) } }
    end

    def self.needs_review?(proposal, recording)
      release = proposal.existing
      return true unless release&.catalog_verified_at

      base = proposal.construction.base
      date = [ release.release_year, release.release_month, release.release_day ].compact.map { |part| part.to_s.rjust(2, "0") }.join("-")
      return true if date != base.data["date"] || current_edition(release) != base.data["id"]

      expected = base.slots.map { |slot| [ slot[:medium], slot[:position], slot.dig(:recording, "id") ] }
      actual = release.catalog_track_slots.base_sequence.order(:medium, :position).includes(:recording).map do |slot|
        [ slot.medium, slot.position, slot.evidence_recording_mbid ]
      end
      return true if actual != expected

      edition_ids = proposal.construction.appearances.pluck("id")
      expected_additions = proposal.construction.additional_slots.map do |slot|
        [ *slot.values_at(:edition_mbid, :appearance_date, :medium, :position), slot.dig(:recording, "id") ]
      end
      actual_additions = release.catalog_track_slots.additional_appearances.where(edition_mbid: edition_ids)
        .includes(:recording).map do |slot|
          [ slot.edition_mbid, slot.appearance_date, slot.medium, slot.position, slot.evidence_recording_mbid ]
        end
      (expected_additions - actual_additions).any? || recording.nil? || !release.catalog_track_slots.exists?(recording_id: recording.id)
    end

    def self.current_edition(release)
      RecordingResolution::ReleaseTracklist.new(release).evidence.fetch("edition_mbid")
    rescue ArgumentError
      release.ingested_from_release_mbid
    end

    def self.head(release)
      return unless release

      fields = release.attributes.values_at("id", "release_year", "release_month", "release_day", "catalog_verified_at", "ingested_from_release_mbid")
      fields << current_edition(release)
      slots = release.catalog_track_slots.order(:id).pluck(:id, :recording_id, :title, :edition_mbid, :appearance_date, :medium, :position, :source_recording_mbid, :track_mbid, :duration_ms, :source_artist_credit)
      Digest::SHA256.hexdigest([ fields, slots ].to_json)
    end

    def self.apply!(proposal, request, assessment, corrected_release: nil)
      construction = proposal.construction
      requests = Array(assessment.evidence["requests"]) + Array(assessment.evidence["reused_publication_requests"])
      provenance = Struct.new(:provenance).new(requests.uniq)
      Store.new(request, provenance).release(construction.base.data, construction.base.slots,
        strict_collection: true, checked_editions: construction.appearances,
        additional_slots: construction.additional_slots, corrected_release:, first_publication_compilation: construction.first_publication_compilation)
    end
  end
end
