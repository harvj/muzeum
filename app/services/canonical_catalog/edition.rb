module CanonicalCatalog
  class Edition
    MAX_TRACKS = 200

    attr_reader :data, :slots

    def initialize(data, mbid, recording_mbid: nil)
      @data = data
      raise Store::Unverified, "Release edition identity could not be verified" unless data && data["id"] == mbid

      @slots = Array(data["media"]).flat_map do |medium|
        tracks = medium["tracks"]
        unless !medium["extra-track-layout"] && medium["position"].is_a?(Integer) && medium["position"].positive? &&
            tracks.is_a?(Array) && medium["track-count"] == tracks.length
          raise Store::Unverified, "Provider track listing is incomplete"
        end

        tracks.map { |track| slot(medium["position"], track) }
      end.sort_by { |track| track.values_at(:medium, :position) }
      if slots.empty? || slots.size > MAX_TRACKS || slots.map { |track| track.values_at(:medium, :position) }.uniq.size != slots.size
        raise Store::Unverified, "Track listing is empty, exceeds the import limit, or has conflicting positions"
      end
      if recording_mbid && slots.none? { |track| track.dig(:recording, "id") == recording_mbid }
        raise Store::Unverified, "Selected recording is absent from this release edition"
      end
    end

    def self.mispressing?(data)
      data["disambiguation"].to_s.match?(/\bmispress(?:ed|ing)?\b/i)
    end

    def self.original_context?(data, compilation: false)
      collection_context?(data, compilation:) && data["date"] == data.dig("release-group", "first-release-date")
    end

    def self.collection_context?(data, compilation: false)
      group = data["release-group"] || {}
      comparable_title = group["title"].blank? || RecordingResolution::DiscoveryTitle.match?(
        RecordingResolution::DiscoveryTitle.album_base(data["title"]), group["title"])
      secondary = Array(group["secondary-types"])
      supported = secondary.empty? || (compilation && secondary == [ "Compilation" ] && group["primary-type"] == "Album")
      comparable_title && Clients::Musicbrainz::MBID.match?(group["id"].to_s) && data["status"] == "Official" && data["date"].present? &&
        group["first-release-date"].present? &&
        supported && group["primary-type"].in?(%w[Album Single EP])
    end

    private

    def slot(medium, track)
      recording = track["recording"]
      unless recording.is_a?(Hash) && track["position"].is_a?(Integer) && track["position"].positive?
        raise Store::Unverified, "A track slot lacks a recording or position"
      end

      Store.mbid!(recording["id"])
      Store.name!(recording["title"])
      recording = recording.merge("artist-credit" => track["artist-credit"]) if recording["artist-credit"].blank?
      { medium:, position: track["position"], number: track["number"], track_mbid: Store.mbid!(track["id"]),
        title: Store.name!(track["title"]), source_recording_mbid: recording.fetch("id"),
        duration_ms: track["length"].is_a?(Integer) && track["length"].positive? ? track["length"] : nil,
        source_artist_credit: track["artist-credit"].presence || recording["artist-credit"], recording: }
    end
  end
end
