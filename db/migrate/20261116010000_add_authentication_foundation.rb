class AddAuthenticationFoundation < ActiveRecord::Migration[8.1]
  def up
    change_column_null :users, :lastfm_username, true
    add_column :users, :email_address, :string
    add_column :users, :password_digest, :string
    add_column :users, :activated_at, :datetime
    add_column :users, :disabled_at, :datetime
    add_index :users, "lower(email_address)", unique: true, name: "index_users_on_normalized_email"
    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :sessions, :expires_at
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Retain login identities and sessions; use compatible code rollback"
  end
end
