class MakeImportRunBoundariesUtc < ActiveRecord::Migration[8.1]
  def change
    add_column :import_runs, :range_start_at, :datetime
    add_column :import_runs, :range_end_at, :datetime

    remove_column :import_runs, :start_date, :date
    remove_column :import_runs, :end_date, :date

    add_index :import_runs, [ :user_id, :range_start_at, :range_end_at ], name: "index_import_runs_on_user_and_range"
    add_index :import_runs, :range_end_at

    remove_column :users, :last_imported_at, :datetime

    remove_column :import_runs, :status, :string, null: false, default: "pending"
    add_column :import_runs, :status, :integer, null: false, default: 0
  end
end
