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
        .flat_map { |recording| recording["releases"] || [] }
        .group_by { |release| release.dig("release-group", "id") }
        .map { |_, releases| build_candidate(releases) }
        .compact
    end

    private

    attr_reader :recordings

    # --------------------------------------------------
    # Core
    # --------------------------------------------------

    def build_candidate(releases)
      return nil if releases.empty?

      chosen = choose_release(releases)

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
        formats: formats_from(chosen),
        country: chosen["country"],
        track_count: chosen["track-count"]
      )
    end

    # --------------------------------------------------
    # Selection logic
    # --------------------------------------------------

    def choose_release(releases)
      releases_with_dates = releases.select { |r| r["date"].present? }
      releases_with_dates = releases if releases_with_dates.empty?

      by_country = releases_with_dates.group_by { |r| r["country"] }

      chosen_country = choose_country(by_country)

      best_dated(by_country[chosen_country])
    end

    def choose_country(by_country)
      countries = by_country.keys.compact

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
  end
end
