class CatalogTrackSlot < ApplicationRecord
  scope :base_sequence, -> { edition_slots_supported? ? where(edition_mbid: nil) : all }
  scope :additional_appearances, -> { edition_slots_supported? ? where.not(edition_mbid: nil) : none }

  def self.edition_slots_supported?
    column_names.include?("edition_mbid")
  end

  belongs_to :release
  belongs_to :recording
end
