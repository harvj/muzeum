module CanonicalLibraryHelper
  def catalog_title(entry)
    entry.is_a?(Artist) ? entry.name : entry.title
  end

  def catalog_link(entry)
    entity_link catalog_title(entry), catalog_entry_path(entry)
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

  def catalog_artists(entry)
    credits = entry.is_a?(Release) ? entry.release_artists : entry.recording_artists
    safe_join(credits.sort_by { |credit| [ credit.position || Float::INFINITY, credit.id ] }.map { |credit| catalog_link(credit.artist) }, ", ")
  end

  def verified_recording_credit(recording)
    credits = CatalogRevision.where(entity_type: "Recording", entity_id: recording.id)
      .where("evidence ? 'artist_credit'").order(id: :desc).pick(:evidence)&.fetch("artist_credit", nil)
    return catalog_artists(recording) if credits.blank?

    artists = recording.artists.index_by(&:mbid)
    return catalog_artists(recording) unless credits.all? { |credit| artists.key?(credit["artist_mbid"]) }

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
