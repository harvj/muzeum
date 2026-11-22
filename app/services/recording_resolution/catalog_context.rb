module RecordingResolution
  class CatalogContext
    def initialize(candidates, releases)
      @recordings = Recording.where(mbid: candidates.pluck("id")).index_by(&:mbid)
      artist_ids = candidates.flat_map { |candidate| credit_ids(candidate) }
      @artists = Artist.where(mbid: artist_ids).index_by(&:mbid)
      release_ids = candidates.flat_map do |candidate|
        [ candidate.dig("local_release_context", "edition_mbid"), candidate.dig("release_discovery", "id"),
          *Array(candidate["releases"]).pluck("id") ]
      end
      @releases = Release.where(ingested_from_release_mbid: release_ids.compact + releases.keys)
        .where.not(catalog_verified_at: nil).index_by(&:ingested_from_release_mbid)
    end

    def rows(candidate, release_id)
      credits = credit_ids(candidate)
      recording = @recordings[candidate["id"]]
      release = @releases[release_id]
      [
        [ "Artist", (@artists[credits.first] if credits.one?), ("Multiple credited artists" if credits.many?) ],
        [ "Recording", recording, nil ],
        [ "Release", release, ("Supporting release unknown" if release_id.blank?) ]
      ]
    end

    private

    def credit_ids(candidate)
      Array(candidate["artist-credit"]).map { |credit| credit.dig("artist", "id") }.uniq
    end
  end
end
