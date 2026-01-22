class ReleaseCandidate
  ATTRS = [
    :source,
    :release_group_mbid,
    :release_group_title,
    :primary_type,
    :secondary_types,
    :release_year,
    :release_month,
    :release_day,
    :representative_release_mbid,
    :artist_names,
    :track_count,
    :country,
    :formats,
    :db_match
  ]

  attr_accessor(*ATTRS)

  def initialize(**attrs)
    attrs.each { |k, v| public_send("#{k}=", v) }
  end

  def to_h
    ATTRS.index_with { |a| public_send(a) }
  end

  def source_label
    source.to_s.capitalize
  end

  def release_date_label
    return release_year.to_s if release_month.nil?
    return "#{release_year}-#{release_month.to_s.rjust(2, "0")}" if release_day.nil?

    "#{release_year}-#{release_month.to_s.rjust(2, "0")}-#{release_day.to_s.rjust(2, "0")}"
  end

  def display_label
    parts = []
    parts << release_group_title
    parts << "(#{release_date_label})"
    parts << "[#{primary_type}]" if primary_type
    parts << "— #{artist_names.join(", ")}" if artist_names.any?
    parts.join(" ")
  end
end
