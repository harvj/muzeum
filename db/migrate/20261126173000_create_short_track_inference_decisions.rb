class CreateShortTrackInferenceDecisions < ActiveRecord::Migration[8.1]
  def change
    create_table :short_track_inference_decisions do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :release, null: false, foreign_key: true, index: false
      t.references :before_play, null: false, foreign_key: { to_table: :scrobbles }
      t.references :after_play, null: false, foreign_key: { to_table: :scrobbles }
      t.references :recording, null: false, foreign_key: true
      t.references :predecessor, foreign_key: { to_table: :short_track_inference_decisions }, index: { unique: true }
      t.string :decision, null: false
      t.jsonb :evidence, null: false
      t.datetime :created_at, null: false
    end
    add_index :short_track_inference_decisions, %i[user_id release_id before_play_id after_play_id recording_id id],
      name: "index_short_track_inference_history"
    add_check_constraint :short_track_inference_decisions,
      "decision IN ('confirmed', 'rejected') AND before_play_id <> after_play_id",
      name: "valid_short_track_inference_decision"
  end
end
