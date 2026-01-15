class CreateScrobblesTable < ActiveRecord::Migration[8.1]
  def change
    create_table :scrobbles do |t|
      t.bigint :user_id, null: false
      t.datetime :played_at, null: false
      t.jsonb :payload, null: false
      t.timestamps
    end

    add_index :scrobbles, [ :user_id, :played_at ], unique: true, name: "index_scrobbles_on_user_and_played_at"
    add_index :scrobbles, :played_at
    add_index :scrobbles, :user_id
  end
end
