class CreateIngestEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :ingest_events do |t|
      t.references :recording_surface, null: false
      t.string  :event_type, null: false
      t.string  :subject_type
      t.integer :subject_id
      t.jsonb   :data
      t.timestamps
    end

    remove_column :recording_artists, :role, :string, null: false, default: "primary"
    add_column :recording_artists, :role, :integer, null: false, default: 0
  end
end
