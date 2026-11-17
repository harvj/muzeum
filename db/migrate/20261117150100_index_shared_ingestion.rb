class IndexSharedIngestion < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!
  def up
    add_index :scrobbles, [ :lastfm_account_id, :source_fingerprint ], unique: true, algorithm: :concurrently
    add_index :scrobbles, [ :lastfm_account_id, :played_at, :id ], algorithm: :concurrently
    add_index :import_runs, :lastfm_account_id, unique: true, where: "status IN (0,1)", name: :one_active_import_per_account, algorithm: :concurrently
    remove_index :import_runs, name: :one_active_import_per_user, algorithm: :concurrently
  end
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
