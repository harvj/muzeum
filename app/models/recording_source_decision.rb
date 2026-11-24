class RecordingSourceDecision < ApplicationRecord
  belongs_to :recording

  def self.heads(mbids)
    where(source_mbid: mbids).select("DISTINCT ON (source_mbid) *").order(:source_mbid, id: :desc).index_by(&:source_mbid)
  end

  def self.resolve(mbid)
    heads([ mbid ])[mbid]&.recording || Recording.find_by(mbid:)
  end

  def self.lock!
    connection.execute("SELECT pg_advisory_xact_lock(23710427, 1)")
  end

  # Revision affects future lookups and source slots. Historical listening
  # decisions continue to point to the recordings that the listener confirmed.
  def self.revise!(source:, recording:, expected_head:, actor:, reason:, **evidence)
    mbid = CanonicalCatalog::Store.mbid!(source.fetch("id"))
    raise ArgumentError if actor.blank? || reason.blank?

    transaction do
      lock!
      previous = heads([ mbid ])[mbid]
      raise ActiveRecord::StaleObjectError.new(previous || recording || new, "revise recording source") unless previous&.id == expected_head
      exact = Recording.find_by(mbid:)
      if recording.nil?
        raise ArgumentError, "A separate identity requires an existing source decision" unless previous
        recording = exact || Recording.create!(mbid:, title: CanonicalCatalog::Store.name!(source["title"]),
          duration_ms: source["length"])
      end
      if exact && exact != recording
        raise CanonicalCatalog::Store::Unverified, "The source already has a canonical recording; review the existing identity separately"
      end

      revision = create!(source_mbid: mbid, recording:, actor:, evidence: evidence.merge(source:, reason:))
      CatalogTrackSlot.where(source_recording_mbid: mbid).where.not(recording_id: recording.id).update_all(recording_id: recording.id)
      revision
    end
  end
end
