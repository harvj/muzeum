module RecordingResolution
  class ReleaseProvenance
    VERSIONED_TRACK = /\b(?:instrumental|live|remix|alternate take|orchestral)\b/i
    AUDIO_BONUS_FORMAT = /\A(?:CD(?:-R)?|Digital Media|Cassette|(?:\d+" )?Vinyl)\z/i
    Appearance = Data.define(:edition, :medium, :track, :comparison)
    Program = Data.define(:edition, :medium, :tracks)

    attr_reader :established, :editions, :appearances, :programs

    def initialize(evidence, contexts:, releases:)
      @established = (releases + contexts.filter_map(&:existing)).uniq(&:id).filter_map do |release|
        ReleaseTracklist.new(release)
      rescue ArgumentError
        nil
      end
      groups = (established.map { |tracklist| tracklist.release.release_group_mbid } +
        contexts.map { |proposal| proposal.construction.base.data.dig("release-group", "id") }).compact.uniq
      evidence_editions = self.class.editions(evidence)
      @editions = evidence_editions.select { |edition| groups.include?(edition.data.dig("release-group", "id")) }
      admitted_editions = established.map { |tracklist| tracklist.evidence.fetch("edition_mbid") }
      bases = established.to_h do |tracklist|
        edition = editions.find { |item| item.data["id"] == tracklist.evidence.fetch("edition_mbid") }
        slots = tracklist.slots.map do |slot|
          edition&.slots&.find do |source|
            source.values_at(:medium, :position, :source_recording_mbid) == [ slot.medium, slot.position, slot.evidence_recording_mbid ]
          end || { source_recording_mbid: slot.evidence_recording_mbid, title: slot.title, duration_ms: slot.duration_ms || slot.recording.duration_ms,
            recording: { "id" => slot.evidence_recording_mbid, "title" => slot.recording.title },
            source_artist_credit: slot.source_artist_credit }
        end
        [ tracklist.release.release_group_mbid, slots ]
      end
      contexts.group_by { |item| item.construction.base.data.dig("release-group", "id") }.each do |group, proposals|
        bases[group] ||= proposals.flat_map { |proposal| proposal.construction.base.slots }
          .uniq { |slot| slot[:track_mbid] }
      end
      @appearances = []
      @programs = []
      primary_editions = contexts.map { |proposal| proposal.construction.base.data["id"] }
      @editions = editions.reject do |edition|
        id = edition.data["id"]
        admitted_editions.include?(id) || (established.empty? && primary_editions.include?(id))
      end
      @editions.each { |edition| compare_edition(edition, bases[edition.data.dig("release-group", "id")]) }
    end

    def self.editions(evidence)
      Array(evidence["construction_editions"]).filter_map do |data|
        next unless Clients::Musicbrainz::MBID.match?(data["id"].to_s)

        CanonicalCatalog::Edition.new(data, data["id"])
      rescue CanonicalCatalog::Store::Unverified
        nil
      end.uniq { |edition| edition.data["id"] }
    end

    def self.checked_recording?(evidence, mbid)
      editions(evidence).any? { |edition| edition.slots.any? { |slot| slot[:source_recording_mbid] == mbid } }
    end

    private

    def compare_edition(edition, base)
      return if base.blank?

      base_ids = base.pluck(:source_recording_mbid).to_set
      Array(edition.data["media"]).each do |medium|
        tracks = edition.slots.select { |slot| slot[:medium] == medium["position"] }
        distinct = []
        tracks.each do |track|
          next if base_ids.include?(track[:source_recording_mbid])

          comparison = base.map { |slot| CanonicalCatalog::TrackComparison.compare(track, slot) }
          next if comparison.include?(:equivalent)

          result = comparison.all?(:different) ? :different : :uncertain
          appearances << Appearance.new(edition.data, medium, track, result)
          distinct << track if result == :different
        end
        next unless CanonicalCatalog::Edition.collection_context?(edition.data) && medium["position"] > 1 &&
          AUDIO_BONUS_FORMAT.match?(medium["format"].to_s) && distinct.size >= 2 && distinct.size == tracks.size &&
          distinct.all? do |track|
            !track.dig(:recording, "video") &&
              (track[:title].match?(VERSIONED_TRACK) || track.dig(:recording, "disambiguation").to_s.match?(VERSIONED_TRACK))
          end

        programs << Program.new(edition.data, medium, tracks)
      end
    end
  end
end
