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
    links = credits.map do |credit|
      artist = credit.artist
      badges ? catalog_link(artist) : entity_link(artist.name, catalog_entry_path(artist))
    end
    safe_join(links, ", ")
  end

  def catalog_release_date(release, selection: @release_selection)
    date = selection ? selection.date(release) : EffectiveReleaseDate.for(release)
    return "Date unknown" unless date.iso

    day = date.first_day
    label = case date.iso.length
    when 4 then date.iso
    when 7 then day.strftime("%B %Y")
    else day.strftime("%B %-d, %Y")
    end
    tag.time(label, datetime: date.iso, class: "catalog-release-date")
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

  def listening_history_option(label, query)
    return tag.span(label, aria: { current: "true" }) unless query

    listening_history_link(label, query)
  end

  def listening_history_link(label, query, **options)
    link_to label, catalog_entry_path(@entry, **query), **options,
      data: { turbo_frame: "catalog-entity", turbo_action: "advance" }
  end

  def listening_window_arrow(glyph, label, date, query)
    if date
      listening_history_link glyph, query.merge(start: date.iso8601), class: "listening-window-arrow", aria: { label: }
    else
      tag.button glyph, type: "button", disabled: true, class: "listening-window-arrow", aria: { label: }
    end
  end

  def listening_calendar_labels(timeline, grouping, spacing:, from_newest: false)
    if grouping == "months"
      quarters = { 1 => "%Y", 4 => "%b", 7 => "%b", 10 => "%b" }
      return timeline.each_with_index.filter_map do |(date, _), i|
        [ i, date.strftime(quarters.fetch(date.month)) ] if quarters.key?(date.month)
      end.to_h
    end

    years = grouping == "years"
    format = { "years" => "%Y", "days" => "%m-%d" }.fetch(grouping)
    transitions = timeline.each_index.select { |i| timeline[i].first.yday == 1 } unless years
    reserved = Set.new
    labels = {}
    Array(transitions).each do |i|
      labels[i] = timeline[i].first.strftime("%Y")
      reserved.merge((i - spacing + 1)...(i + spacing))
    end
    timeline.each_with_index do |(date, _), i|
      offset = from_newest ? timeline.size - i - 1 : i
      next unless (offset % spacing).zero? && !reserved.include?(i)

      labels[i] = date.strftime(format)
    end
    labels
  end

  def recording_duration(milliseconds)
    return "Unknown" unless milliseconds

    minutes, seconds = (milliseconds / 1000).divmod(60)
    return format("%d:%02d:%02d", minutes / 60, minutes % 60, seconds) if minutes >= 60

    format("%d:%02d", minutes, seconds)
  end

  def compact_listening_time(milliseconds)
    "#{number_with_delimiter((milliseconds / 60_000.0).round)} min"
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
