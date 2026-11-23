module RecordingResolution
  class CatalogContext
    def initialize(candidates)
      @recordings = Recording.where(mbid: candidates.pluck("id"))
        .includes(:admitted_releases, recording_artists: :artist).index_by(&:mbid)
      artist_ids = candidates.flat_map { |candidate| credit_ids(candidate) }
      @artists = Artist.where(mbid: artist_ids).index_by(&:mbid)
    end

    def rows(candidate)
      recording = @recordings[candidate["id"]]
      artists = if recording
        recording.recording_artists.map(&:artist).uniq
      else
        @artists.values_at(*credit_ids(candidate)).compact
      end
      self.class.rows(recording, artists:, worker_enabled: CatalogImport.worker_enabled?)
    end

    def self.rows(recording, artists: recording&.recording_artists&.map(&:artist)&.uniq || [], worker_enabled: CatalogImport.worker_enabled?)
      releases = recording&.admitted_releases&.select(&:catalog_verified_at)&.sort_by { |release| [ release.title, release.id ] } || []
      state = CatalogImport.latest_recording_work(recording.id)&.state if recording
      pending = worker_enabled && state.in?(CatalogImport::ACTIVE)
      release_status = if pending
        "Checking recording metadata…"
      elsif recording
        "Release verification pending"
      else
        "No verified catalog match"
      end
      [
        [ "Artist", artists, nil ],
        [ "Recording", [ recording ].compact, nil ],
        [ "Release", releases, release_status ]
      ]
    end

    def self.stream(recording)
      "resolution_catalog:#{recording.id}"
    end

    def self.target(recording)
      "catalog_context_#{recording.id}"
    end

    private

    def credit_ids(candidate)
      Array(candidate["artist-credit"]).map { |credit| credit.dig("artist", "id") }.uniq
    end
  end
end
