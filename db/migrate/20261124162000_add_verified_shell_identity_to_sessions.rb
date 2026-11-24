class AddVerifiedShellIdentityToSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :shell_username, :string
    add_column :sessions, :shell_username_issued_at, :bigint
  end
end
