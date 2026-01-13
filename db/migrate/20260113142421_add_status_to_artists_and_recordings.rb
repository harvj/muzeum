class AddStatusToArtistsAndRecordings < ActiveRecord::Migration[8.1]
  def change
    add_column :artists, :status, :integer, null: false, default: 0
    add_column :recordings, :status, :integer, null: false, default: 0

    remove_column :recording_artists, :confidence_score, :float
    add_column :recordings, :confidence, :float
    add_column :artists, :confidence, :float

    remove_column :recording_artists, :source, :string, null: false, default: "inferred"
    add_column :recordings, :source, :string, null: false, default: "lastfm"
    add_column :artists, :source, :string, null: false, default: "lastfm"

    rename_column :artists, :musicbrainz_id, :mbid
    rename_column :recordings, :musicbrainz_id, :mbid

    add_column :artists, :merged_into_id, :bigint
    add_column :recordings, :merged_into_id, :bigint
    add_index :artists, :merged_into_id
    add_index :recordings, :merged_into_id
  end
end
