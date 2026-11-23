module CanonicalLibraryHelper
  def catalog_title(entry)
    entry.is_a?(Artist) ? entry.name : entry.title
  end

  def catalog_link(entry, title: catalog_title(entry))
    safe_join([ musical_identity_badge(entry), entity_link(title, catalog_entry_path(entry)) ])
  end

  def musical_identity(entry)
    @musical_identities&.fetch([ entry.class.name, entry.id ], nil)
  end

  def inherited_musical_identity(entry)
    @inherited_musical_identities&.fetch([ entry.class.name, entry.id ], nil)
  end

  def effective_musical_colors(entry)
    inherited_musical_identity(entry)&.fetch(:colors) || musical_identity(entry)&.colors || []
  end

  def musical_identity_attributes(entry)
    colors = effective_musical_colors(entry)
    %i[identity_first identity_second identity_third].zip(colors).filter_map { |position, color| [ position, color ] if color }.to_h
  end

  def musical_identity_badge(entry, detailed: false)
    colors = effective_musical_colors(entry)
    return if colors.empty? && !detailed

    label = colors.map { |color| MusicalIdentity::Palette::COLORS.fetch(color) }.to_sentence.presence || "unclassified"
    if (inherited = inherited_musical_identity(entry))
      label += " · inherited from #{inherited.fetch(:artists).map(&:name).to_sentence}"
    end
    link_to(detailed ? "#guide-assignment" : "#guide-colors", class: "identity-badge",
      data: { action: "guide#open", **musical_identity_attributes(entry) },
      aria: { label: "Musical identity for #{catalog_title(entry)}: #{label}" }) do
      tag.span(class: "identity-swatch", aria: { hidden: true })
    end
  end

  def catalog_entry_path(entry, **options)
    if @public_profile
      public_send("public_profile_#{entry.model_name.singular_route_key}_path", @public_profile, entry, **options)
    else
      polymorphic_path(entry, **options)
    end
  end

  def catalog_index_path(section, **options)
    if @public_profile
      public_send("public_profile_#{section}_path", @public_profile, **options)
    else
      public_send("#{section}_path", **options)
    end
  end

  def catalog_import_path(entry)
    case entry
    when Artist then import_artist_path(entry)
    when Release then import_release_path(entry)
    when Recording then import_recording_path(entry)
    end
  end

  def catalog_artists(entry, badges: true)
    credits = entry.is_a?(Release) ? entry.release_artists : entry.recording_artists
    links = credits.sort_by { |credit| [ credit.position || Float::INFINITY, credit.id ] }.map do |credit|
      artist = credit.artist
      badges ? catalog_link(artist) : entity_link(artist.name, catalog_entry_path(artist))
    end
    safe_join(links, ", ")
  end

  def catalog_release_date(release)
    return unless release.release_year

    year, month, day = release.release_year, release.release_month, release.release_day
    timestamp = format("%04d", year)
    label = year.to_s
    if month.in?(1..12)
      timestamp += format("-%02d", month)
      label = "#{Date::MONTHNAMES.fetch(month)} #{year}"
      if day && Date.valid_date?(year, month, day)
        timestamp += format("-%02d", day)
        label = "#{Date::MONTHNAMES.fetch(month)} #{day}, #{year}"
      end
    end
    tag.time(label, datetime: timestamp, class: "catalog-release-date")
  end

  def verified_catalog_credit(entry)
    credits = CatalogRevision.where(entity_type: entry.class.name, entity_id: entry.id)
      .where("evidence ? 'artist_credit'").order(id: :desc).pick(:evidence)&.fetch("artist_credit", nil)
    return catalog_artists(entry) if credits.blank?

    artists = entry.artists.index_by(&:mbid)
    return catalog_artists(entry) unless credits.pluck("artist_mbid").to_set == artists.keys.to_set

    safe_join(credits.flat_map do |credit|
      artist = artists.fetch(credit.fetch("artist_mbid"))
      [ entity_link(credit["credited_name"].presence || artist.name, catalog_entry_path(artist)), credit["join_phrase"].to_s ]
    end)
  end

  def import_status(request, verified: false)
    case request&.state
    when "pending" then request.failure.present? ? "Pending retry" : "Pending enrichment"
    when "refreshing" then "Refreshing"
    when "imported" then "Imported"
    when "incomplete" then "Incomplete"
    when "failed" then "Failed · retry available"
    else verified ? "Imported" : "Enrichment available"
    end
  end

  def recording_duration(milliseconds)
    return "Unknown" unless milliseconds

    minutes, seconds = (milliseconds / 1000).divmod(60)
    return format("%d:%02d:%02d", minutes / 60, minutes % 60, seconds) if minutes >= 60

    format("%d:%02d", minutes, seconds)
  end

  def compact_listening_time(milliseconds)
    minutes, seconds = (milliseconds / 1000).divmod(60)
    return "#{minutes / 60}h #{minutes % 60}m" if minutes >= 60
    return "#{minutes}m" if minutes.positive?

    "#{seconds}s"
  end

  def estimated_listening_time(totals)
    return "Time unknown" if totals.plays.positive? && totals.known_durations.zero?

    compact_listening_time(totals.milliseconds)
  end

  def duration_coverage(totals)
    "Duration known for #{totals.known_durations} of #{totals.plays} plays."
  end

  def review_factor_label(key, factor)
    return factor["explanation"] unless key == "catalog_release_appearance"

    case factor.dig("provenance", "relationship")
    when "matching_catalog_caption"
      if factor["weight"] == 2
        "Checked tracklist and matching Last.fm album caption (historical scoring)"
      else
        "Checked catalog tracklist contains this recording"
      end
    when "related_catalog_title"
      "Checked catalog tracklist contains this recording"
    else
      factor["explanation"]
    end
  end

  def observed_text(value, label)
    return "#{label} missing" if value.nil?
    return "#{label} blank" if value.empty?

    value
  end

  def browser_time(time, clock: false, date_only: false)
    content_tag(:time, time.utc.strftime(date_only ? "%Y-%m-%d" : "%Y-%m-%d %H:%M UTC"),
      datetime: time.utc.iso8601, data: { controller: "local-time", local_time_clock_value: clock, local_time_date_only_value: date_only })
  end
end
