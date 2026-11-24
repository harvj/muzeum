class CreateRecordingSourceDecisions < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_source_decisions do |t|
      t.uuid :source_mbid, null: false
      t.references :recording, null: false, foreign_key: true
      t.string :actor, null: false
      t.jsonb :evidence, null: false
      t.timestamps
    end
    add_index :recording_source_decisions, [ :source_mbid, :id ]
  end
end
