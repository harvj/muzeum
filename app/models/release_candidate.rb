class ReleaseCandidate
  attr_reader \
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
    :formats

  def initialize(
    source:,
    release_group_mbid: nil,
    release_group_title:,
    primary_type:,
    secondary_types: [],
    release_year: nil,
    release_month: nil,
    release_day: nil,
    representative_release_mbid: nil,
    artist_names: [],
    track_count: nil,
    country: nil,
    formats: []
  )
    @source                      = source
    @release_group_mbid          = release_group_mbid
    @release_group_title         = release_group_title
    @primary_type                = primary_type
    @secondary_types             = secondary_types
    @release_year                = release_year
    @release_month               = release_month
    @release_day                 = release_day
    @representative_release_mbid = representative_release_mbid
    @artist_names                = artist_names
    @track_count                 = track_count
    @country                     = country
    @formats                     = formats
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

  def from_database?
    source == :database
  end

  def from_musicbrainz?
    source == :musicbrainz
  end
end
