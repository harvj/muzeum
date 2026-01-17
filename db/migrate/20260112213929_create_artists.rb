class CreateArtists < ActiveRecord::Migration[8.1]
  def change
    #
    # USERS
    #
    create_table :users do |t|
      t.string :lastfm_username, null: false
      t.timestamps
    end
    add_index :users, :lastfm_username, unique: true

    #
    # ARTISTS
    #
    create_table :artists do |t|
      t.string :name, null: false
      t.string :musicbrainz_id
      t.timestamps
    end
    add_index :artists, :musicbrainz_id, unique: true
    add_index :artists, :name

    #
    # RECORDINGS
    #
    create_table :recordings do |t|
      t.string :title, null: false
      t.integer :duration_ms
      t.string :musicbrainz_id
      t.timestamps
    end
    add_index :recordings, :musicbrainz_id, unique: true
    add_index :recordings, :title

    #
    # RECORDING_ARTISTS (many-to-many, ordered, role-aware)
    #
    create_table :recording_artists do |t|
      t.references :recording, null: false, foreign_key: true
      t.references :artist, null: false, foreign_key: true
      t.string :role, null: false, default: "primary"
      t.integer :position
      t.float :weight, null: false, default: 1.0
      t.string :source, null: false, default: "inferred"
      t.float :confidence_score
      t.timestamps
    end
    add_index :recording_artists, [ :recording_id, :artist_id ], unique: true

    #
    # DAILY_LISTENS (aggregated fact table)
    #
    create_table :daily_listens do |t|
      t.references :user, null: false, foreign_key: true
      t.references :recording, null: false, foreign_key: true
      t.date :date, null: false
      t.integer :listen_count, null: false, default: 0
      t.bigint :total_duration_ms, null: false, default: 0
      t.integer :year, null: false, limit: 2
      t.timestamps
    end
    add_index :daily_listens, [ :user_id, :date ]
    add_index :daily_listens, [ :user_id, :recording_id ]
    add_index :daily_listens, [ :user_id, :recording_id, :date ], unique: true
    add_index :daily_listens, :year

    #
    # IMPORT_RUNS
    #
    create_table :import_runs do |t|
      t.references :user, null: false, foreign_key: true
      t.date :start_date
      t.date :end_date
      t.string :status, null: false, default: "pending"
      t.integer :scrobbles_processed
      t.integer :recordings_created
      t.integer :artists_created
      t.integer :unmapped_recordings
      t.jsonb :notes
      t.timestamps
    end
    add_index :import_runs, :status
    add_index :import_runs, :created_at
  end
end
