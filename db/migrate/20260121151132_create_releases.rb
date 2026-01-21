class CreateReleases < ActiveRecord::Migration[8.1]
  def change
    create_table :releases do |t|
      t.string  :title, null: false
      t.string  :mbid
      t.string  :release_group_mbid
      t.string  :primary_type
      t.integer :release_year
      t.integer :release_month
      t.integer :release_day
      t.string  :source, null: false, default: "musicbrainz"
    end

    add_index :releases, :mbid, unique: true
    add_index :releases, :release_group_mbid

    create_table :release_artists do |t|
      t.references :release, null: false, foreign_key: true
      t.references :artist,  null: false, foreign_key: true
      t.integer :position
      t.timestamps
    end

    add_index :release_artists, [ :release_id, :artist_id ], unique: true

    create_table :release_recordings do |t|
      t.references :release,   null: false, foreign_key: true
      t.references :recording, null: false, foreign_key: true
      t.integer :position, null: false
      t.timestamps
    end

    add_index :release_recordings, [ :release_id, :recording_id ], unique: true
    add_index :release_recordings, [ :release_id, :position ], unique: true

    remove_column :artists, :confidence, :float, null: false, default: 0.0
    remove_column :artists, :status, :integer, null: false, default: 0
    remove_column :artists, :source, :string, null: false, default: "lastfm"
    remove_column :artists, :merged_into_id, :bigint
  end
end
