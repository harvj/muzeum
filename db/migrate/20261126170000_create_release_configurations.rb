class CreateReleaseConfigurations < ActiveRecord::Migration[8.1]
  def change
    create_table :release_configurations do |t|
      t.references :release, null: false, foreign_key: true
      t.string :edition_mbid, null: false
      t.string :source_date
      t.string :source_country
      t.string :digest, null: false
      t.jsonb :tracks, null: false
      t.jsonb :provenance, null: false
      t.datetime :created_at, null: false
    end
    add_index :release_configurations, %i[release_id edition_mbid digest], unique: true, name: "index_release_configuration_snapshots"
    add_index :release_configurations, %i[release_id id], unique: true

    create_table :release_configuration_decisions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :release, null: false, foreign_key: true
      t.references :release_configuration
      t.datetime :created_at, null: false
    end
    add_foreign_key :release_configuration_decisions, :release_configurations,
      column: %i[release_id release_configuration_id], primary_key: %i[release_id id]
    add_index :release_configuration_decisions, %i[user_id release_id id], name: "index_release_configuration_decision_history"
  end
end
