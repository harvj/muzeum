class CreateMusicalIdentityDecisions < ActiveRecord::Migration[8.1]
  def change
    create_table :musical_identity_decisions do |t|
      t.references :entity, polymorphic: true, null: false, index: false
      t.references :user, null: false, foreign_key: true
      t.string :colors, array: true, default: [], null: false
      t.text :rationale
      t.timestamps
    end
    add_index :musical_identity_decisions, [ :entity_type, :entity_id, :id ]
  end
end
