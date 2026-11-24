class CatalogTrackSlot < ApplicationRecord
  scope :base_sequence, -> { where(edition_mbid: nil) }
  scope :additional_appearances, -> { where.not(edition_mbid: nil) }

  belongs_to :release
  belongs_to :recording

  def evidence_recording_mbid
    source_recording_mbid || recording.mbid
  end
end
