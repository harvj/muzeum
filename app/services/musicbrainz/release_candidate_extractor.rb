module Musicbrainz
  class ReleaseCandidateExtractor
    def self.call(recordings)
      new(recordings).call
    end

    def initialize(recordings)
      @recordings = Array(recordings)
    end

    def call
      recordings.flat_map { |recording| extract_from_recording(recording) }
    end

    private

    attr_reader :recordings

    def extract_from_recording(recording)
      Array(recording["releases"]).map do |release|
        Musicbrainz::ReleaseCandidate.new(
          # release identity
          release_mbid: release["id"],
          release_title: release["title"],
          release_date: release["date"],
          country: release["country"],
          formats: formats_for(release),

          # release group (semantic family, not canon)
          release_group_mbid: release.dig("release-group", "id"),
          release_group_primary_type: release.dig("release-group", "primary-type"),
          release_group_secondary_types: Array(
            release.dig("release-group", "secondary-types")
          ),

          # recording identity
          recording_mbid: recording["id"],
          recording_title: recording["title"],
          recording_disambiguation: recording["disambiguation"],

          # artist context
          artist_credit: artist_credit(recording)
        )
      end
    end

    def artist_credit(recording)
      Array(recording["artist-credit"]).map do |credit|
        credit.dig("artist", "name") || credit["name"]
      end.compact
    end

    def formats_for(release)
      return [] unless release["media"]

      release["media"]
        .map { |medium| medium["format"] }
        .compact
        .uniq
    end
  end
end
