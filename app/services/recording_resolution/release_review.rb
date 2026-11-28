module RecordingResolution
  # Reviewed provider identifiers are lookup leads. Only complete checked
  # tracklists and exact recording intersections support a program proposal.
  class ReleaseReview
    REVIEWS = JSON.parse(Rails.root.join("config/catalog/release_reviews.json").read).freeze

    attr_reader :group, :policy

    def initialize(evidence)
      @evidence = evidence
      @editions = ReleaseProvenance.editions(evidence).index_by { |edition| edition.data.fetch("id") }
      @group = @editions.values.filter_map { |edition| edition.data.dig("release-group", "id") }.find { |id| REVIEWS.key?(id) }
      @policy = REVIEWS[@group]
    end

    def configurations
      policy.fetch("configurations").filter_map { |id| @editions[id] if matches_group?(@editions[id]) }
    end

    def disputed
      policy.fetch("disputed").filter_map { |id, note| [ @editions[id], note ] if matches_group?(@editions[id]) }
    end

    def programs
      known = @editions.values.select { |edition| matches_group?(edition) }.flat_map(&:slots).pluck(:source_recording_mbid).to_set
      Array(@evidence["reviewed_adjacent_programs"]).filter_map do |data|
        next unless policy.fetch("adjacent").include?(data["id"]) && data.dig("release-group", "id") != group &&
          CanonicalCatalog::Edition.original_context?(data) && !CanonicalCatalog::Edition.mispressing?(data)

        edition = CanonicalCatalog::Edition.new(data, data.fetch("id"))
        matches = edition.slots.select { |slot| known.include?(slot[:source_recording_mbid]) }
        [ edition, matches ] if matches.any?
      rescue CanonicalCatalog::Store::Unverified
        nil
      end
    end

    def other_tracks
      represented = (configurations.flat_map(&:slots) + programs.flat_map { |_, matches| matches })
        .pluck(:source_recording_mbid).to_set
      alternate = @editions.values.select { |edition| matches_group?(edition) } - configurations - disputed.map(&:first)
      alternate.flat_map(&:slots).reject { |track| represented.include?(track.fetch(:source_recording_mbid)) }
        .uniq { |track| track.fetch(:source_recording_mbid) }.sort_by { |track| track.fetch(:title).downcase }
    end

    def refresh(client, session)
      planned = policy.fetch("configurations") - configurations.map { |edition| edition.data.fetch("id") }
      planned += policy.fetch("adjacent") - programs.map { |edition, _| edition.data.fetch("id") }
      missing = []
      fetched = planned.filter_map do |id|
        data = client.edition(session, id, catalog: true)
        raise CanonicalCatalog::Store::Unverified unless data && data["status"] == "Official"

        edition = CanonicalCatalog::Edition.new(data, id)
        if policy.fetch("configurations").include?(id)
          raise CanonicalCatalog::Store::Unverified unless matches_group?(edition)
        else
          raise CanonicalCatalog::Store::Unverified unless data.dig("release-group", "id") != group &&
            CanonicalCatalog::Edition.original_context?(data)
        end
        data
      rescue CanonicalCatalog::Store::Unverified, ProviderError => error
        raise if error.is_a?(ProviderError) && error.deferred

        missing << id
        nil
      end
      coverage = @evidence.fetch("reviewed_recording_browses", {}).dup
      policy.fetch("incomplete_browses").each do |id|
        next if coverage.dig(id, "complete")

        appearances = []
        begin
          appearances = client.provenance_releases(session, id) { |page| appearances = page }
          coverage[id] = { "complete" => true, "appearances" => appearances }
        rescue CanonicalCatalog::Store::Unverified, ProviderError => error
          raise if error.is_a?(ProviderError) && error.deferred

          coverage[id] = { "complete" => false, "appearances" => appearances.presence || coverage.dig(id, "appearances") || [] }
        end
      end
      configurations, programs = fetched.partition { |edition| edition.dig("release-group", "id") == group }
      @evidence.merge(
        "construction_editions" => (configurations + Array(@evidence["construction_editions"])).uniq { |item| item["id"] },
        "reviewed_recording_browses" => coverage,
        "reviewed_adjacent_programs" => (programs + Array(@evidence["reviewed_adjacent_programs"])).uniq { |item| item["id"] },
        "reviewed_release_lookup" => { "missing" => missing, "attempted" => planned, "reference" => policy.fetch("reference") }
      )
    end

    private

    def matches_group?(edition)
      edition && edition.data.dig("release-group", "id") == group && edition.data["status"] == "Official"
    end
  end
end
