module RecordingResolution
  # Publication evidence is keyed by recording identity. The observed album and
  # the edition that contributed recording-match evidence are never inputs.
  class RecordingOrigins
    BROWSE_PAGE = 25

    def initialize(musicbrainz, session)
      @musicbrainz = musicbrainz
      @session = session
    end

    def call(recording_ids, retained:)
      editions = retained.index_by { |edition| edition["id"] }
      histories = recording_ids.index_with do |id|
        investigate(id, editions)
      end
      { "recording_publications" => histories, "construction_editions" => editions.values }
    end

    private

    def investigate(id, editions)
      recording = @musicbrainz.verify_recording(@session, id, catalog: true)["data"]
      return { "pending" => true } unless recording && recording["id"] == id

      begin
        appearances = @musicbrainz.recording_releases(@session, id, limit: BROWSE_PAGE)
      rescue ProviderError, CanonicalCatalog::Store::Unverified => error
        raise if error.is_a?(ProviderError) && error.deferred

        appearances = Array(recording["releases"])
        raise if appearances.empty?
        browse_incomplete = true
      end
      appearances = (appearances + Array(recording["releases"])).uniq { |row| row["id"] }
      dated = appearances.select { |row| %w[Official Withdrawn].include?(row["status"]) && publication_date?(row["date"]) }
      # A year or month alone cannot establish an earlier day than an
      # independently dated appearance inside that period.
      earliest = dated.reject do |row|
        dated.any? { |other| other["date"].start_with?(row["date"] + "-") }
      end.min_by { |row| [ row["date"], row["id"] ] }
      history = {
        "checked_at" => Time.current.iso8601, "appearances" => appearances, "earliest_publication" => (earliest&.slice("id", "title", "date") unless browse_incomplete),
        "original_groups" => [], "pending_groups" => [], "verified_recording" => recording.except("releases"),
        "appearance_browse_incomplete" => browse_incomplete == true
      }
      # A mispressing can document an exact appearance without identifying the
      # release group's intended program. Verify only the referenced edition.
      appearances.select { |row| CanonicalCatalog::Edition.mispressing?(row) }.each do |row|
        verified_edition(row.fetch("id"), row.dig("release-group", "id"), editions, compilation: false)
      rescue CanonicalCatalog::Store::Unverified
        next
      end
      groups = appearances.select do |row|
        CanonicalCatalog::Edition.collection_context?(row) && !CanonicalCatalog::Edition.mispressing?(row)
      end
        .group_by { |row| row.dig("release-group", "id") }
      if groups.empty? && !browse_incomplete && earliest && CanonicalCatalog::Edition.original_context?(earliest, compilation: true) &&
          earliest.dig("release-group", "secondary-types") == [ "Compilation" ] &&
          dated.select { |row| row["date"] == earliest["date"] }.all? { |row| row.dig("release-group", "id") == earliest.dig("release-group", "id") }
        group = earliest.dig("release-group", "id")
        groups = { group => [ earliest ] }
        history["first_publication_compilation_group"] = group
      end
      provider_failure = nil
      groups.sort_by { |group, refs| [ refs.first.dig("release-group", "primary-type") == "Album" ? 0 : 1, group ] }.each do |group, refs|
        metadata = refs.first.fetch("release-group")
        references = @musicbrainz.collection_editions(@session, group, limit: BROWSE_PAGE)
        compilation = history["first_publication_compilation_group"] == group
        checked = original_editions(metadata, references, editions, compilation:)
        original = checked.map { |edition| CanonicalCatalog::Edition.new(edition, edition.fetch("id")) }
        raise CanonicalCatalog::Store::Unverified if CanonicalCatalog::Construction.originals(original, compilation:).empty?
        # The original program can omit a recording known only from an additional edition.
        if checked.none? { |edition| includes?(edition, id) }
          retained = refs.select { |row| editions.key?(row["id"]) }.filter_map { |row| editions[row["id"]] }
          appearance = retained.find { |edition| includes?(edition, id) }
          unless appearance
            reference = refs.min_by { |row| [ row.fetch("date"), row.fetch("id") ] }
            appearance = verified_edition(reference.fetch("id"), group, editions, compilation:)
          end
          raise CanonicalCatalog::Store::Unverified unless includes?(appearance, id)
        end
        history["original_groups"] << group
        history["edition_coverage"] ||= {}
        history["edition_coverage"][group] = compare_editions(group, references, checked, editions, compilation:)
      rescue ProviderError => error
        raise if error.deferred

        provider_failure ||= error
        history["pending_groups"] << group
        (history["group_errors"] ||= {})[group] = { "http_status" => error.http_status, "reason" => "Provider unavailable" }.compact
      rescue CanonicalCatalog::Store::Unverified
        history["pending_groups"] << group
      end
      raise provider_failure if provider_failure && history["original_groups"].empty?

      history
    rescue CanonicalCatalog::Store::Unverified
      { "pending" => true }
    end

    def original_editions(group, references, editions, compilation:)
      refs = references.select do |row|
        row["status"] == "Official" && row["date"] == group["first-release-date"] &&
          (group["title"].blank? || DiscoveryTitle.match?(DiscoveryTitle.album_base(row["title"]), group["title"]))
      end
      raise CanonicalCatalog::Store::Unverified if refs.empty? || refs.size > EditionDiscovery::MAX_ORIGINAL_LOOKUPS

      refs.map do |row|
        checked = verified_edition(row.fetch("id"), group.fetch("id"), editions, compilation:)
        raise CanonicalCatalog::Store::Unverified unless CanonicalCatalog::Edition.original_context?(checked, compilation:)

        checked
      end
    end

    def compare_editions(group, references, originals, editions, compilation:)
      original_ids = originals.pluck("id")
      official = references.select { |row| row["status"] == "Official" && publication_date?(row["date"]) }
      remaining = official.reject { |row| original_ids.include?(row["id"]) }.sort_by { |row| row.values_at("date", "id") }
      budget = [ EditionDiscovery::MAX_ORIGINAL_LOOKUPS - original_ids.size, 0 ].max
      remaining.first(budget).each do |row|
        verified_edition(row.fetch("id"), group, editions, compilation:)
      rescue ProviderError => error
        raise if error.deferred
      rescue CanonicalCatalog::Store::Unverified
        next
      end
      verified, unchecked = official.pluck("id").partition { |id| editions.key?(id) }
      { "verified" => verified.sort, "unchecked" => unchecked.sort }
    end

    def verified_edition(id, group, editions, compilation:)
      data = editions[id] || @musicbrainz.edition(@session, id, catalog: true)
      unless data && data.dig("release-group", "id") == group && CanonicalCatalog::Edition.collection_context?(data, compilation:)
        raise CanonicalCatalog::Store::Unverified
      end

      CanonicalCatalog::Edition.new(data, id)
      editions[id] = data
    end

    def includes?(edition, id)
      Array(edition["media"]).any? do |medium|
        Array(medium["tracks"]).any? { |track| track.dig("recording", "id") == id }
      end
    end

    def publication_date?(date)
      return false unless date.to_s.match?(/\A\d{4}(?:-\d{2}){0,2}\z/)

      Date.iso8601([ date, *Array.new(3 - date.split("-").length, "01") ].join("-"))
      true
    rescue Date::Error
      false
    end
  end
end
