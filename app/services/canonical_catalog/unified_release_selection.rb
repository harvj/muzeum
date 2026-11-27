module CanonicalCatalog
  class UnifiedReleaseSelection
    def initialize(assessment, user)
      @assessment = assessment
      @user = user
      @review = RecordingResolution::ReleaseReview.new(assessment.evidence)
    end

    # Called inside the existing surface-decision transaction, with the
    # listener and catalog identity locks already held.
    def apply!(configuration_ids:, preferred_id:, program_ids:)
      raise Store::Unverified, "No reviewed programs are available" unless @review.policy

      configurations = select_editions(@review.configurations, configuration_ids)
      programs = select_editions(@review.programs.map(&:first), program_ids)
      preferred = configurations.find { |edition| edition.data["id"] == preferred_id }
      if preferred_id.present? && !preferred || configurations.many? && !preferred
        raise Store::Unverified, "Choose a primary configuration from the checked editions."
      end

      preferred ||= configurations.first
      apply_album!(configurations, preferred) if preferred
      programs.each do |edition|
        next if existing_release(edition)

        admit!(edition, "adjacent_release_admission")
      end
    end

    private

    def select_editions(available, ids)
      ids = Array(ids)
      choices = available.select { |edition| ids.include?(edition.data["id"]) }
      raise Store::Unverified, "A selected release is no longer in the verified review." unless choices.size == ids.size

      choices
    end

    def existing_release(edition)
      records = Release.where(release_group_mbid: edition.data.dig("release-group", "id")).limit(2).to_a
      raise Store::Unverified, "Review conflicting catalog releases before continuing." if records.many?

      records.first
    end

    def apply_album!(editions, preferred)
      album = existing_release(preferred) || admit!(preferred, "reviewed_configuration_admission")
      snapshots = editions.to_h do |edition|
        snapshot = ReleaseConfiguration.retain!(album, edition.data, provenance: {
          "assessment_id" => @assessment.id, "assessment_digest" => @assessment.digest
        })
        [ edition.data["id"], snapshot ]
      end
      ReleaseConfigurationDecision.select!(@user, album, snapshots.fetch(preferred.data["id"]))
    end

    def admit!(edition, kind)
      request = CatalogImport.create!(kind:, state: "imported", entity_id: @assessment.id, due_at: Time.current,
        context: { reviewer_id: @user.id, assessment_id: @assessment.id,
          assessment_digest: @assessment.digest, edition_mbid: edition.data.fetch("id") })
      evidence = Struct.new(:provenance).new(Array(@assessment.evidence["requests"]))
      Store.new(request, evidence).release(edition.data, edition.slots, strict_collection: true)
    end
  end
end
