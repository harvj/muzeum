class ReleaseConfiguration < ApplicationRecord
  belongs_to :release

  Track = Data.define(:medium, :position, :title, :duration_ms, :source_recording_mbid, :recording) do
    def recording_id
      recording&.id
    end
  end

  def readonly?
    persisted?
  end

  def self.retain!(release, data, provenance:)
    mbid = CanonicalCatalog::Store.mbid!(data["id"])
    unless release.catalog_verified_at && release.release_group_mbid.present? &&
        data.dig("release-group", "id") == release.release_group_mbid &&
        data["status"] == "Official" && !CanonicalCatalog::Edition.mispressing?(data)
      raise CanonicalCatalog::Store::Unverified, "This edition is not a verified configuration of this release"
    end

    edition = CanonicalCatalog::Edition.new(data, mbid)
    tracks = edition.slots.map { |track| track.except(:recording) }
    evidence = provenance.merge(
      "release_group_mbid" => release.release_group_mbid,
      "title" => data["title"], "disambiguation" => data["disambiguation"],
      "media" => Array(data["media"]).map { |medium| medium.slice("position", "format", "title", "track-count") }
    )
    source_date = data["date"].presence
    source_country = data["country"].presence
    digest = Digest::SHA256.hexdigest([ tracks, source_date, source_country, evidence ].to_json)
    find_or_create_by!(release:, edition_mbid: mbid, digest:) do |snapshot|
      snapshot.assign_attributes(tracks:, provenance: evidence, source_date:, source_country:)
    end
  end

  def ordered_tracks
    ids = tracks.pluck("source_recording_mbid")
    recordings = self.class.recordings_by_source(ids)
    tracks.map do |track|
      source = track.fetch("source_recording_mbid")
      Track.new(*track.values_at("medium", "position", "title", "duration_ms"), source, recordings[source])
    end
  end

  def self.recordings_by_source(ids)
    exact = Recording.where(mbid: ids).index_by(&:mbid)
    aliases = RecordingSourceDecision.heads(ids)
    alias_recordings = Recording.where(id: aliases.values.map(&:recording_id)).index_by(&:id)
    exact.merge(aliases.transform_values { |decision| alias_recordings.fetch(decision.recording_id) })
  end
end
