class WalkBackIngestEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_surfaces, :ingest_log, :jsonb, default: [], null: false

    drop_table :ingest_events do |t|
      t.references :recording_surface, null: false
      t.string  :event_type, null: false
      t.string  :subject_type
      t.integer :subject_id
      t.jsonb   :data
      t.timestamps
    end
  end
end
