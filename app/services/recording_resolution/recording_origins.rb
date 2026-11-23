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

      appearances = @musicbrainz.recording_releases(@session, id, limit: BROWSE_PAGE)
      dated = appearances.select { |row| %w[Official Withdrawn].include?(row["status"]) && publication_date?(row["date"]) }
      # A year or month alone cannot establish an earlier day than an
      # independently dated appearance inside that period.
      earliest = dated.reject do |row|
        dated.any? { |other| other["date"].start_with?(row["date"] + "-") }
      end.min_by { |row| [ row["date"], row["id"] ] }
      history = {
        "checked_at" => Time.current.iso8601, "appearances" => appearances, "earliest_publication" => earliest&.slice("id", "title", "date"),
        "original_groups" => [], "pending_groups" => []
      }
      groups = appearances.select { |row| CanonicalCatalog::Edition.collection_context?(row) }
        .group_by { |row| row.dig("release-group", "id") }
      groups.sort_by { |group, refs| [ refs.first.dig("release-group", "primary-type") == "Album" ? 0 : 1, group ] }.each do |group, refs|
        metadata = refs.first.fetch("release-group")
        checked = original_editions(metadata, editions)
        original = checked.map { |edition| CanonicalCatalog::Edition.new(edition, edition.fetch("id")) }
        raise CanonicalCatalog::Store::Unverified if CanonicalCatalog::Construction.originals(original).empty?
        # The original program can omit a recording known only from an additional edition.
        if checked.none? { |edition| includes?(edition, id) }
          retained = refs.select { |row| editions.key?(row["id"]) }.filter_map { |row| editions[row["id"]] }
          appearance = retained.find { |edition| includes?(edition, id) }
          unless appearance
            reference = refs.min_by { |row| [ row.fetch("date"), row.fetch("id") ] }
            appearance = verified_edition(reference.fetch("id"), group, editions)
          end
          raise CanonicalCatalog::Store::Unverified unless includes?(appearance, id)
        end
        history["original_groups"] << group
      rescue CanonicalCatalog::Store::Unverified
        history["pending_groups"] << group
      end
      history
    rescue CanonicalCatalog::Store::Unverified
      { "pending" => true }
    end

    def original_editions(group, editions)
      refs = @musicbrainz.collection_editions(@session, group.fetch("id"), limit: BROWSE_PAGE).select do |row|
        row["status"] == "Official" && row["date"] == group["first-release-date"] &&
          (group["title"].blank? || DiscoveryTitle.match?(DiscoveryTitle.album_base(row["title"]), group["title"]))
      end
      raise CanonicalCatalog::Store::Unverified if refs.empty?

      refs.map do |row|
        checked = verified_edition(row.fetch("id"), group.fetch("id"), editions)
        raise CanonicalCatalog::Store::Unverified unless CanonicalCatalog::Edition.original_context?(checked)

        checked
      end
    end

    def verified_edition(id, group, editions)
      data = editions[id] || @musicbrainz.edition(@session, id, catalog: true)
      unless data && data.dig("release-group", "id") == group && CanonicalCatalog::Edition.collection_context?(data)
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
