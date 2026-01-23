class AddRecordingSurfaceToScrobbles < ActiveRecord::Migration[8.1]
  def change
    remove_column :recording_surfaces, :confidence, :float, default: 0.5, null: false
    remove_column :recording_surfaces, :source, :string, default: "lastfm", null: false
    change_column :recording_surfaces, :recording_id, :bigint, null: true
    add_column :recording_surfaces, :ingested_release_id, :bigint, null: true

    remove_column :recordings, :confidence, :float, default: 0.0, null: false
    remove_column :recordings, :merged_into_id, :bigint
    remove_column :recordings, :source, :string, default: "lastfm", null: false
    remove_column :recordings, :status, :integer, default: 0, null: false
  end
end
