module Musicbrainz
  class ReleaseCandidateExtractor
    def self.call(recordings)
      new(recordings).call
    end

    def initialize(recordings)
      @recordings = Array(recordings)
    end

    def call
      recordings
        .flat_map do |recording|
          Array(recording["releases"]).map do |release|
            {
              "recording_mbid" => recording["id"],
              "recording_title" => recording["title"],
              "release" => release
            }
          end
        end
        .group_by { |h| h.dig("release", "release-group", "id") }
        .map { |release_group_mbid, entries| build_candidate(release_group_mbid, entries) }
        .compact
    end

    private

    attr_reader :recordings

    # --------------------------------------------------
    # Core
    # --------------------------------------------------

    def build_candidate(release_group_mbid, entries)
      return nil if entries.empty?

      releases = entries.map { |e| e["release"] }

      db_info = db_release_for_group(release_group_mbid)

      chosen = if db_info
        find_db_matching_release(releases, db_info[:ingested_from_release_mbid])
      end

      chosen ||= choose_representative_release(releases)

      matched_recordings =
        entries
          .select { |e| e["release"]["id"] == chosen["id"] }
          .map do |e|
            {
              "mbid" => e["recording_mbid"],
              "title" => e["recording_title"]
            }
          end

      ReleaseCandidate.new(
        source: :musicbrainz,
        release_group_mbid: chosen.dig("release-group", "id"),
        release_group_title: chosen.dig("release-group", "title"),
        primary_type: chosen.dig("release-group", "primary-type"),
        secondary_types: secondary_types(chosen["release-group"]),
        release_year: year_from(chosen["date"]),
        release_month: month_from(chosen["date"]),
        release_day: day_from(chosen["date"]),
        representative_release_mbid: chosen["id"],
        artist_names: chosen["artist-credit"].map { |a| a["name"] },
        track_count: chosen["track-count"],
        country: chosen["country"],
        formats: formats_from(chosen),
        matched_tracks: matched_tracks_from(chosen["media"]),
        matched_recordings: matched_recordings,
        db_match:
          if db_info && chosen["id"] == db_info[:ingested_from_release_mbid]
            db_info.merge(
              ingested_from_release_mbid: chosen["id"]
            )
          end
      )
    end

    # --------------------------------------------------
    # Selection logic
    # --------------------------------------------------

    def choose_representative_release(releases)
      releases_with_dates = releases.select { |r| r["date"].present? }
      releases_with_dates = releases if releases_with_dates.empty?

      by_country = releases_with_dates.group_by { |r| r["country"] }

      chosen_country = choose_country(by_country)

      best_dated(by_country[chosen_country])
    end

    def choose_country(by_country)
      countries = by_country.keys.compact

      return nil if countries.blank?
      return countries.first if countries.size == 1
      return "JP" if countries == [ "JP" ]

      non_jp = countries.reject { |c| c == "JP" || %w[XW XE].include?(c) }
      non_jp = countries if non_jp.empty?

      non_jp
        .map { |c| [ c, by_country[c] ] }
        .max_by { |(_, releases)| country_score(releases) }
        .first
    end

    def country_score(releases)
      [
        releases.size,
        releases.count { |r| full_date?(r["date"]) }
      ]
    end

    def best_dated(releases)
      releases.min_by { |r| date_sort_key(r["date"]) }
    end

    # --------------------------------------------------
    # Helpers
    # --------------------------------------------------

    def db_release_for_group(release_group_mbid)
      row = Release
        .where(release_group_mbid: release_group_mbid)
        .pick(:id, :ingested_from_release_mbid)

      return nil unless row

      {
        release_id: row[0],
        ingested_from_release_mbid: row[1]
      }
    end

    def find_db_matching_release(releases, ingested_mbid)
      return nil unless ingested_mbid
      releases.find { |r| r["id"] == ingested_mbid }
    end

    def date_sort_key(date)
      y, m, d = parse_date(date)
      [
        y || 9999,
        m || 12,
        d || 31,
        completeness_penalty(m, d)
      ]
    end

    def completeness_penalty(m, d)
      return 2 if m.nil?
      return 1 if d.nil?
      0
    end

    def full_date?(date)
      _, m, d = parse_date(date)
      m && d
    end

    def parse_date(date)
      return [ nil, nil, nil ] if date.blank?
      parts = date.split("-").map(&:to_i)
      [ parts[0], parts[1], parts[2] ]
    end

    def year_from(date)  = parse_date(date)[0]
    def month_from(date) = parse_date(date)[1]
    def day_from(date)   = parse_date(date)[2]

    def formats_from(release)
      Array(release["media"]).map { |m| m["format"] }.compact.uniq
    end

    def secondary_types(release_group)
      Array(release_group["secondary-types"]).compact
    end

    def matched_tracks_from(chosen_media)
      media = Array(chosen_media)
      media.flat_map do |m|
        m["tracks"] || m["track"] || []
      end
    end
  end
end
