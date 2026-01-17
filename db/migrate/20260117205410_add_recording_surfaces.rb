class AddRecordingSurfaces < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_surfaces do |t|
      t.references :recording, null: false, foreign_key: true

      # Observed strings
      t.string :artist_name, null: false
      t.string :track_name,  null: false
      t.string :album_name

      # Observed identifiers (claims, not truth)
      t.string :artist_mbid
      t.string :track_mbid
      t.string :album_mbid

      # Lookup + learning
      t.string  :normalized_key, null: false
      t.integer :observed_count, null: false, default: 1
      t.float   :confidence, null: false, default: 0.5

      t.string :source, null: false, default: "lastfm"

      t.timestamps
    end

    add_index :recording_surfaces, :normalized_key, unique: true
    add_index :recording_surfaces, :track_mbid
    add_index :recording_surfaces, :artist_mbid
  end
end
