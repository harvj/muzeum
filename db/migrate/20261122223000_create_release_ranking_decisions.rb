class CreateReleaseRankingDecisions < ActiveRecord::Migration[8.1]
  def change
    create_table :release_ranking_decisions do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :release, null: false, foreign_key: true, index: false
      t.boolean :included, null: false
      t.timestamps
    end
    add_index :release_ranking_decisions, [ :user_id, :release_id, :id ]
  end
end
