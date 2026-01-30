module Releases
  class ReleaseIngestor
    include SimpleLogger

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

    attr_reader :surface, :main_artists

    def ready?
      surface.release_candidates.present? &&
        surface.chosen_release_candidate.present?
    end

    def candidate
      @candidate ||= begin
        raw = surface.chosen_release_candidate
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
      count = Scrobble.where(recording_surface_id: surface.id).update_all(recording_id: recording.id)
      log("Updated recording on #{count} scrobble(s)")
    end

    # ------------------------------------------------------------------
    # Existing release path
    # ------------------------------------------------------------------

    def ingest_existing_release!
      release = Release.find(candidate.db_match["release_id"])

      canonical = release.release_recordings
                          .includes(:recording)
                          .find { |rr| rr.recording.title.casecmp?(surface.track_name) }
                          &.recording

      log("Assigning EXISTING release id=#{release.id} title=#{release.title} | recording id=#{canonical.id} title=#{canonical.title}")
      [ release, canonical ]
    end

    # ------------------------------------------------------------------
    # New release path
    # ------------------------------------------------------------------

    def ingest_new_release!
      payload = Clients::Musicbrainz
        .new
        .fetch_release(candidate.representative_release_mbid)

      @main_artists = ingest_artists!(payload)
      release = ingest_release!(payload)
      link_release_artists!(release, main_artists)

      canonical_recordings =
        ingest_release_recordings!(release, payload)

      canonical =
        canonical_recordings.find do |recording|
          recording.title.casecmp?(surface.track_name)
        end

      log("Assigning CREATED release id=#{release.id} title=#{release.title} | recording id=#{canonical.id} title=#{canonical.title}")
      [ release, canonical ]
    end

    # ------------------------------------------------------------------
    # Artist / Release creation
    # ------------------------------------------------------------------

    def ingest_artists!(payload)
      Array(payload["artist-credit"]).map do |credit|
        artist_data = credit["artist"]

        created = false
        artist = Artist.find_or_create_by!(mbid: artist_data["id"]) do |a|
          created = true
          a.name = artist_data["name"]
        end
        log_ingest(artist, created, :name)

        artist
      end
    end

    def ingest_release!(payload)
      year, month, day = release_date_parts(payload)

      created = false
      release = Release.find_or_create_by!(ingested_from_release_mbid: payload["id"]) do |r|
        created = true
        r.title              = payload["title"]
        r.release_group_mbid = payload.dig("release-group", "id")
        r.release_year       = year
        r.release_month      = month
        r.release_day        = day
        r.primary_type       = map_primary_type(payload)
        r.secondary_type     = map_secondary_type(payload)
      end
      log_ingest(release, created, :title)

      release
    end

    def link_release_artists!(release, artists)
      release_artists = []

      artists.each_with_index do |artist, index|
        created = false
        ra = ReleaseArtist.find_or_create_by!(
          release: release,
          artist: artist
        ) do |i|
          created = true
          i.position = index
        end

        release_artists << ra
        log_ingest(ra, created, "artist-name", "release-title")
      end

      release_artists
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
            if video_track?(track["recording"])
              store_log("Skipping video track > title=#{track["title"]} position=#{track["position"]}")
              next
            end

            created = false
            rec = Recording.find_or_create_by!(mbid: track.dig("recording", "id")) do |r|
              created = true
              r.title       = track["title"]
              r.duration_ms = track["length"]
            end
            log_ingest(rec, created, :title)

            ReleaseRecording.create!(
              release: release,
              recording: rec,
              position: global_position
            )

            ingest_recording_artists!(rec, track)

            global_position += 1
            recordings << rec
          end
        end

      recordings
    end

    def ingest_recording_artists!(recording, track)
      Array(track.dig("recording", "artist-credit")).each_with_index do |credit, index|
        artist_data = credit["artist"]

        artist_created = false
        artist = Artist.find_or_create_by!(mbid: artist_data["id"]) do |a|
          artist_created = true
          a.name = artist_data["name"]
        end

        RecordingArtist.create!(
          recording: recording,
          artist: artist,
          position: index
        )

        log_ingest(artist, artist_created, :name) unless main_artists.map(&:id).include?(artist.id)
      end
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

    def video_track?(recording_data)
      recording_data["video"]
    end

    def store_log(message)
      message.strip!

      surface.ingest_log << {
        at: Time.current.iso8601,
        message: message
      }
      surface.save!

      log message
    end

    def log_ingest(record, created, *attrs)
      action = created ? "CREATED" : "FOUND"
      event_type ||= action.downcase

      data = attrs.to_h do |a|
        [ a, resolve_attr_path(record, a) ]
      end

      message =
        "#{action} #{record.class.name} id=#{record.id} " +
        data.map { |k, v| "#{k}=#{v}" }.join(" ")

      store_log(message)
    end

    def resolve_attr_path(record, attr)
      path =
        case attr
        when Symbol
          [ attr ]
        when String
          attr.split("-").map(&:to_sym)
        else
          raise ArgumentError, "Invalid attr #{attr.inspect}"
        end

      path.reduce(record) do |obj, method|
        return nil unless obj.respond_to?(method)
        obj.public_send(method)
      end
    end
  end
end
