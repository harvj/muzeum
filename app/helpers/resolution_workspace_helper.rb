module ResolutionWorkspaceHelper
  def resolution_release_contexts(assessment, candidates)
    candidates.index_with do |candidate|
      id = candidate.fetch("id")
      identity = resolution_recording_identity(assessment, id)
      CanonicalCatalog::ReviewedConstruction.for(assessment, id, source_ids: identity.source_ids || [ id ])
    end
  end

  def resolution_recording_identity(assessment, mbid)
    (@resolution_recording_identities ||= {})[[ assessment.id, mbid ]] ||= CanonicalCatalog::RecordingIdentity.new(assessment, mbid)
  end

  def resolution_distinct_recording_count(assessment, candidates)
    candidates.map do |candidate|
      mbid = candidate.fetch("id")
      identity = resolution_recording_identity(assessment, mbid)
      identity.recording ? [ :canonical, identity.recording.id ] : [ :sources, (identity.source_ids || [ mbid ]).sort ]
    end.uniq.size
  end

  def resolution_selected_candidate(candidates, ranking, contexts, requested, current)
    selected = candidates.find { |candidate| candidate["id"] == requested }
    selected ||= candidates.find { |candidate| candidate["id"] == current }
    return selected if selected

    scores = ranking.to_h { |entry| [ entry["recording_mbid"], entry["score"] ] }
    candidates.find { |candidate| scores[candidate["id"]] == ranking.first["score"] && contexts.fetch(candidate).any? } || candidates.first
  end

  def resolution_edition_options(proposals)
    bases = proposals.map { |item| item.construction.base }
    sequences = bases.map(&:slots)
    difference = (0...sequences.map(&:size).max).find do |index|
      slots = sequences.map { |sequence| sequence[index] }
      slots.any?(&:nil?) || slots.combination(2).any? do |left, right|
        CanonicalCatalog::TrackComparison.compare(left, right) == :different
      end
    end
    bases.map do |base|
      data = base.data
      slot = base.slots[difference] if difference
      label = [ data["title"], data["country"], pluralize(base.slots.size, "track") ].compact
      if slot
        label << "Track #{difference + 1}: #{slot[:title]}"
      elsif difference.nil?
        label << "Source recording identity needs review"
      end
      [ label.join(" · "), data.fetch("id") ]
    end
  end

  def resolution_release_date(date)
    date.match?(/\A\d{4}-\d{2}-\d{2}\z/) ? Date.iso8601(date).strftime("%B %-d, %Y") : date
  end

  def resolution_shared_candidate_labels(candidates)
    groups = candidates.group_by do |candidate|
      [ candidate.fetch("title"), resolution_candidate_credit(candidate), recording_duration(candidate["length"]) ]
    end
    groups.values.select(&:many?).flatten.to_set
  end

  def resolution_candidate_association(candidate, contexts)
    bases = contexts.map { |item| item.construction.base }.sort_by do |base|
      [ base.data.dig("release-group", "primary-type") == "Album" ? 0 : 1, base.data.fetch("date") ]
    end
    slots = bases.to_h do |base|
      [ base, base.slots.index { |slot| slot.dig(:recording, "id") == candidate.fetch("id") } ]
    end
    base, slot = slots.find { |_, match| match }
    unless base
      appearances = Array(candidate["releases"]).select { |release| release["title"].present? && release["date"].present? }
      appearance = appearances.min_by { |release| release.values_at("date", "title").push(release["id"].to_s) }
      return [ appearance["title"], appearance["date"], "Appearance" ].join(" · ") if appearance
      return
    end

    label = [ base.data.fetch("title"), base.data.fetch("date").first(4) ]
    group = base.data.dig("release-group", "id")
    positions = slots.filter_map do |edition, match|
      match if edition.data.dig("release-group", "id") == group
    end
    label << "Track #{slot + 1}" if positions.uniq.size == 1
    label.join(" · ")
  end

  def resolution_candidate_credit(candidate)
    Array(candidate["artist-credit"]).filter_map do |credit|
      credit.dig("artist", "name").presence || credit["name"].presence
    end.join(", ").presence || "Artist credit unavailable"
  end
end
