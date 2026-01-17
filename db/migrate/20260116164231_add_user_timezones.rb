class AddUserTimezones < ActiveRecord::Migration[8.1]
  def change
    change_column :artists, :confidence, :float, null: false, default: 0.0
    change_column :recordings, :confidence, :float, null: false, default: 0.0

    create_table :user_timezones do |t|
      t.references :user, null: false
      t.string :timezone, null: false
      t.datetime :effective_from, null: false
      t.timestamps
    end
  end
end
