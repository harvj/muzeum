module Releases
  class ReleaseIngestor
    def self.call(candidate)
      new(candidate).call
    end

    def initialize(candidate)
      @candidate = candidate
      @client = Clients::Musicbrainz.new
    end

    def call
      ActiveRecord::Base.transaction do
        return release if release_exists?

        fetch_mb_release
        create_artists
        create_release
        create_recordings_and_tracklist
        merge_provisional_recordings

        release
      end
    end

    private

    attr_reader :candidate, :client, :mb_release

    def release_exists?
      Release.exists?(mbid: candidate.representative_release_mbid)
    end

    def release
      @release ||= Release.find_by!(mbid: candidate.representative_release_mbid)
    end

    # -----------------------
    # MB FETCH
    # -----------------------

    def fetch_mb_release
      @mb_release = client.fetch_release(candidate.representative_release_mbid)
    end

    # -----------------------
    # ARTISTS
    # -----------------------

    def create_artists
      mb_release["artist-credit"].each do |credit|
        artist = credit["artist"]

        Artist.find_or_create_by!(mbid: artist["id"]) do |a|
          a.name = artist["name"]
        end
      end
    end

    # -----------------------
    # RELEASE
    # -----------------------

    def create_release
      Release.create!(
        mbid: candidate.representative_release_mbid,
        release_group_mbid: candidate.release_group_mbid,
        title: candidate.release_group_title,
        primary_type: candidate.primary_type,
        secondary_types: candidate.secondary_types,
        year: candidate.release_year,
        month: candidate.release_month,
        day: candidate.release_day,
        country: candidate.country
      )
    end

    # -----------------------
    # TRACKLIST
    # -----------------------

    def create_recordings_and_tracklist
      mb_release["media"].each do |medium|
        medium["tracks"].each do |track|
          recording = Recording.find_or_create_by!(mbid: track["recording"]["id"]) do |r|
            r.title = track["title"]
            r.duration_ms = track["length"]
            r.source = "musicbrainz"
            r.status = :canonical
          end

          ReleaseRecording.find_or_create_by!(
            release: release,
            recording: recording
          ) do |rr|
            rr.position = track["position"].to_i
          end
        end
      end
    end

    # -----------------------
    # MERGING
    # -----------------------

    def merge_provisional_recordings
      release.release_recordings.each do |rr|
        canonical = rr.recording

        provisional_recordings_for(canonical).each do |prov|
          prov.scrobbles.update_all(recording_id: canonical.id)
          prov.update!(merged_into_id: canonical.id, status: :merged)
        end
      end
    end

    def provisional_recordings_for(canonical)
      Recording.where(
        title: canonical.title,
        mbid: nil,
        status: :provisional
      )
    end
  end
end
