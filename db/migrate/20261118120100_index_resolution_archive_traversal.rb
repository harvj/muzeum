class IndexResolutionArchiveTraversal < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :scrobbles, [ :lastfm_account_id, :id ], algorithm: :concurrently,
      name: "index_scrobbles_archive_keyset"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Requires explicit migration review"
  end
end
