module Musicbrainz
  ReleaseCandidate = Struct.new(
    :release_mbid,
    :release_title,
    :release_date,
    :release_type,
    :artist_credit,
    :track_position,
    :recording_mbid,
    :recording_title,
    :recording_disambiguation,
    :country,
    :formats,
    :release_group_mbid,
    :release_group_primary_type,
    :release_group_secondary_types,
    keyword_init: true
  )
end
