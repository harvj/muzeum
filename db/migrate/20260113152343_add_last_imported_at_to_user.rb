class AddLastImportedAtToUser < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :last_imported_at, :datetime
  end
end
