module CanonicalLibraryHelper
  def catalog_title(entry)
    entry.is_a?(Artist) ? entry.name : entry.title
  end

  def catalog_link(entry)
    entity_link catalog_title(entry), polymorphic_path(entry)
  end

  def catalog_index_path(section, **options)
    case section
    when "artists" then artists_path(**options)
    when "releases" then releases_path(**options)
    when "recordings" then recordings_path(**options)
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
    format("%d:%02d", minutes, seconds)
  end

  def observed_text(value, label)
    return "#{label} missing" if value.nil?
    return "#{label} blank" if value.empty?

    value
  end

  def browser_time(time, clock: false)
    content_tag(:time, time.utc.strftime("%Y-%m-%d %H:%M UTC"),
      datetime: time.utc.iso8601, data: { controller: "local-time", local_time_clock_value: clock })
  end
end
