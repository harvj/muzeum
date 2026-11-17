class AddProductionArchive < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :oidc_issuer, :string
    add_column :users, :oidc_subject, :string
    add_index :users, [ :oidc_issuer, :oidc_subject ], unique: true
    add_column :sessions, :grant_token, :text
    add_column :sessions, :verified_at, :datetime
    add_column :sessions, :last_seen_at, :datetime
    create_table :oidc_attempts do |t|
      t.string :state, null: false
      t.string :browser_digest, null: false
      t.string :nonce, null: false
      t.string :verifier, null: false
      t.datetime :expires_at, null: false
    end
    add_index :oidc_attempts, :state, unique: true
    add_column :import_runs, :next_page, :integer, default: 1, null: false
    add_column :import_runs, :upper_bound, :bigint
    add_column :import_runs, :total_pages, :integer
    add_column :import_runs, :expected_count, :bigint
    add_column :import_runs, :last_error, :string
    add_column :import_runs, :last_success_at, :datetime
    add_column :import_runs, :source_username, :string
    add_index :import_runs, :user_id, unique: true, where: 'status IN (0, 1)', name: 'one_active_import_per_user'
    create_table :import_pages do |t|
      t.references :import_run, null: false, foreign_key: true
      t.integer :number, null: false
      t.text :raw_body, null: false
      t.string :checksum, null: false
      t.timestamps
    end
    add_index :import_pages, [ :import_run_id, :number ], unique: true
    add_column :scrobbles, :source_fingerprint, :string
    add_reference :scrobbles, :import_page, foreign_key: true
    remove_index :scrobbles, name: :index_scrobbles_on_user_and_played_at
    add_index :scrobbles, [ :user_id, :played_at ]
    add_index :scrobbles, [ :user_id, :source_fingerprint ], unique: true
  end
end
