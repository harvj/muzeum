class RecordingResolver
  class ResolutionError < StandardError; end

  # Resolve a provisional recording using authoritative MusicBrainz data.
  #
  # Returns the canonical Recording.
  #
  def self.resolve!(
    provisional_recording:,
    mbid:,
    title:
  )
    raise ResolutionError, "Authoritative MBID required" if mbid.blank?

    new(
      provisional_recording: provisional_recording,
      mbid: mbid,
      title: title
    ).resolve!
  end

  def initialize(provisional_recording:, mbid:, title:)
    @provisional = provisional_recording
    @mbid        = mbid
    @title       = title
  end

  def resolve!
    Recording.transaction do
      canonical = Recording.find_by(mbid: mbid)

      if canonical
        merge_provisional_into!(canonical)
        canonical
      else
        promote_provisional_to_canonical!
      end
    end
  end

  private

  attr_reader :provisional, :mbid, :title

  # ---- resolution paths ----

  def promote_provisional_to_canonical!
    provisional.update!(
      mbid: mbid,
      title: title,          # authoritative title wins
      status: :canonical,
      source: "musicbrainz",
      confidence: 1.0
    )

    provisional
  end

  def merge_provisional_into!(canonical)
    return if provisional.id == canonical.id

    reassign_scrobbles!(from: provisional, to: canonical)

    provisional.update!(
      merged_into_id: canonical.id,
      status: :merged
    )
  end

  # ---- helpers ----

  def reassign_scrobbles!(from:, to:)
    Scrobble.where(recording_id: from.id)
            .update_all(recording_id: to.id)
  end
end
