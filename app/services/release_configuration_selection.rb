class ReleaseConfigurationSelection
  def initialize(listener, release_ids)
    @listener = listener
    @release_ids = release_ids
    @configurations = ReleaseConfigurationDecision.latest_for(listener, release_ids)
      .preload(:release_configuration).index_by(&:release_id)
  end

  def configuration(release)
    @configurations[release.id]&.release_configuration
  end

  def date(release)
    EffectiveReleaseDate.for(release, configuration(release))
  end

  def released_within(releases, from: nil, through: nil)
    releases.select { |release| date(release).within?(from:, through:) }
  end

  def newest_first(releases)
    releases.sort_by do |release|
      first_day = date(release).first_day
      [ first_day.nil? ? 1 : 0, -(first_day&.jd || 0), release.title.downcase, release.id ]
    end
  end

  def memberships
    selected = @configurations.transform_values(&:release_configuration).compact
    fallback = ReleaseTrackListeningDecision.included_memberships(@listener, @release_ids)
      .where.not(release_id: selected.keys).distinct.pluck(:release_id, :recording_id)
    recordings = ReleaseConfiguration.recordings_by_source(selected.values.flat_map { |snapshot| snapshot.tracks.pluck("source_recording_mbid") }.uniq)
    selected.each do |release_id, snapshot|
      ids = snapshot.tracks.filter_map { |track| recordings[track.fetch("source_recording_mbid")]&.id }.uniq
      ids.each { |recording_id| fallback << [ release_id, recording_id ] }
    end
    fallback
  end
end
