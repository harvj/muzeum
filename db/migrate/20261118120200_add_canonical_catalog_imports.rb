class AddCanonicalCatalogImports < ActiveRecord::Migration[8.0]
  def change
    create_table :catalog_imports do |t|
      t.string :kind, null: false
      t.bigint :entity_id, null: false
      t.jsonb :context, null: false, default: {}
      t.string :state, null: false, default: "pending"
      t.datetime :due_at, null: false
      t.datetime :lease_until
      t.string :lease_token
      t.integer :attempts, null: false, default: 0
      t.integer :request_count, null: false, default: 0
      t.string :failure
      t.timestamps
      t.index %i[kind entity_id id]
      t.index %i[kind entity_id], unique: true, where: "state IN ('pending', 'refreshing')",
        name: "index_catalog_imports_active_entity"
      t.index %i[state due_at]
      t.check_constraint "state IN ('pending', 'refreshing', 'imported', 'incomplete', 'failed')", name: "catalog_import_state"
      t.check_constraint "(state = 'refreshing') = (lease_token IS NOT NULL AND lease_until IS NOT NULL)",
        name: "catalog_import_lease"
    end

    create_table :catalog_revisions do |t|
      t.references :catalog_import, null: false, foreign_key: true
      t.string :entity_type, null: false
      t.bigint :entity_id, null: false
      t.jsonb :evidence, null: false, default: {}
      t.datetime :created_at, null: false
      t.index %i[entity_type entity_id id]
    end
    reversible do |direction|
      direction.up do
        execute <<~SQL
          CREATE TRIGGER catalog_revisions_immutable BEFORE UPDATE OR DELETE ON catalog_revisions
            FOR EACH ROW EXECUTE FUNCTION muzeum_preserve_source();
          CREATE TRIGGER catalog_revisions_no_truncate BEFORE TRUNCATE ON catalog_revisions
            FOR EACH STATEMENT EXECUTE FUNCTION muzeum_preserve_source();
        SQL
      end
      direction.down do
        execute "DROP TRIGGER catalog_revisions_no_truncate ON catalog_revisions"
        execute "DROP TRIGGER catalog_revisions_immutable ON catalog_revisions"
      end
    end

    create_table :catalog_track_slots do |t|
      t.references :release, null: false, foreign_key: true
      t.references :recording, null: false, foreign_key: true
      t.integer :medium, null: false
      t.integer :position, null: false
      t.string :number
      t.string :track_mbid, null: false
      t.string :title, null: false
      t.index %i[release_id medium position], unique: true
      t.check_constraint "medium > 0 AND position > 0", name: "catalog_track_slot_position"
    end
    add_column :releases, :catalog_country, :string
    add_column :releases, :catalog_verified_at, :datetime
  end
end
