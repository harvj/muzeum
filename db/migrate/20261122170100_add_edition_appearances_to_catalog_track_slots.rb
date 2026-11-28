class AddEditionAppearancesToCatalogTrackSlots < ActiveRecord::Migration[8.1]
  def change
    add_column :catalog_track_slots, :edition_mbid, :string
    add_column :catalog_track_slots, :appearance_date, :string
    add_index :catalog_track_slots, [ :release_id, :edition_mbid, :medium, :position ], unique: true,
      where: "edition_mbid IS NOT NULL", name: "idx_catalog_track_slots_edition_position"
    add_index :catalog_track_slots, [ :release_id, :medium, :position ], unique: true,
      where: "edition_mbid IS NULL", name: "idx_catalog_track_slots_base_position"
    remove_index :catalog_track_slots, [ :release_id, :medium, :position ], unique: true,
      name: "idx_on_release_id_medium_position_5d7e315be8"
  end
end
