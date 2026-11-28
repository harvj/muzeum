class AddSourceProvenanceToCatalogTrackSlots < ActiveRecord::Migration[8.1]
  def change
    add_column :catalog_track_slots, :source_recording_mbid, :string
    add_column :catalog_track_slots, :duration_ms, :integer
    add_column :catalog_track_slots, :source_artist_credit, :jsonb
  end
end
