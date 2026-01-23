# app/services/releases/release_ingestor.rb
module Releases
  class ReleaseIngestor
    def self.call(recording_surface)
      new(recording_surface).call
    end

    def initialize(recording_surface)
      @surface = recording_surface
    end

    def call
      return unless ready?

      ActiveRecord::Base.transaction do
        ingest!
      end
    end

    private

    attr_reader :surface

    def ready?
      surface.release_candidates.present? &&
        surface.chosen_release_candidate_index.present?
    end

    def candidate
      @candidate ||= begin
        raw = surface.release_candidates[surface.chosen_release_candidate_index]
        ReleaseCandidate.new(**raw)
      end
    end

    def ingest!
      release, recording = if candidate.db_match.present?
        ingest_existing_release!
      else
        ingest_new_release!
      end

      surface.update!(
        ingested_release_id: release.id,
        recording_id: recording.id
      )
      Scrobble.where(recording_surface_id: surface.id).update_all(recording_id: recording.id)
    end

    # ------------------------------------------------------------------
    # Existing release path
    # ------------------------------------------------------------------

    def ingest_existing_release!
      release = Release.find(candidate.db_match[:release_id])

      canonical = release.release_recordings
                          .includes(:recording)
                          .find { |rr| rr.recording.title.casecmp?(surface.track_name) }
                          &.recording

      [ release, canonical ]
    end

    # ------------------------------------------------------------------
    # New release path
    # ------------------------------------------------------------------

    def ingest_new_release!
      payload = Clients::Musicbrainz
        .new
        .fetch_release(candidate.representative_release_mbid)

      artists = ingest_artists!(payload)
      release = ingest_release!(payload)
      link_release_artists!(release, artists)

      canonical_recordings =
        ingest_release_recordings!(release, payload)

      canonical =
        canonical_recordings.find do |recording|
          recording.title.casecmp?(surface.track_name)
        end

      [ release, canonical ]
    end

    # ------------------------------------------------------------------
    # Artist / Release creation
    # ------------------------------------------------------------------

    def ingest_artists!(payload)
      Array(payload["artist-credit"]).map do |credit|
        artist_data = credit["artist"]

        Artist.find_or_create_by!(mbid: artist_data["id"]) do |a|
          a.name = artist_data["name"]
        end
      end
    end

    def ingest_release!(payload)
      year, month, day = release_date_parts(payload)

      Release.create!(
        title: payload["title"],
        ingested_from_release_mbid: payload["id"],
        release_group_mbid: payload.dig("release-group", "id"),
        release_year: year,
        release_month: month,
        release_day: day,
        primary_type: map_primary_type(payload),
        secondary_type: map_secondary_type(payload)
      )
    end

    def link_release_artists!(release, artists)
      artists.each_with_index do |artist, index|
        ReleaseArtist.create!(
          release: release,
          artist: artist,
          position: index
        )
      end
    end

    # ------------------------------------------------------------------
    # Tracklist
    # ------------------------------------------------------------------

    def ingest_release_recordings!(release, payload)
      recordings = []
      global_position = 1

      Array(payload["media"])
        .sort_by { |m| m["position"].to_i }
        .each do |medium|
          tracks =
            Array(medium["tracks"]).sort_by do |track|
              track["position"] || Float::INFINITY
            end

          tracks.each do |track|
            rec = Recording.find_or_create_by!(mbid: track.dig("recording", "id")) do |r|
              r.title       = track["title"]
              r.duration_ms = track["length"]
            end

            ReleaseRecording.create!(
              release: release,
              recording: rec,
              position: global_position
            )

            global_position += 1
            recordings << rec
          end
        end

      recordings
    end

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def release_date_parts(payload)
      return [ nil, nil, nil ] unless payload["date"]

      parts = payload["date"].split("-").map(&:to_i)

      year  = parts[0]
      month = parts[1]
      day   = parts[2]

      [ year, month, day ]
    end

    def map_primary_type(payload)
      case payload.dig("release-group", "primary-type")
      when "Album" then :album
      when "EP" then :ep
      when "Single" then :single
      when "Compilation" then :compilation
      else :album
      end
    end

    def map_secondary_type(payload)
      secondary = Array(payload.dig("release-group", "secondary-types"))
      return :reissue if secondary.include?("Reissue")
      return :live if secondary.include?("Live")
      return :soundtrack if secondary.include?("Soundtrack")
      :official
    end
  end
end
