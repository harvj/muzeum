class CreateReleaseTrackListeningDecisions < ActiveRecord::Migration[8.1]
  def change
    create_table :release_track_listening_decisions do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :release, null: false, foreign_key: true, index: false
      t.references :recording, null: false, foreign_key: true, index: false
      t.boolean :included, null: false
      t.timestamps
    end
    add_index :release_track_listening_decisions, [ :user_id, :release_id, :recording_id, :id ],
      name: "index_release_track_listening_on_listener_release_recording"
  end
end
