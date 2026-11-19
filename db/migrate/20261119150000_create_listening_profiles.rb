class CreateListeningProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :listening_profiles do |t|
      t.references :lastfm_account, null: false, foreign_key: true, index: { unique: true }
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.string :ownership_basis, null: false
      t.text :ownership_reference, null: false
      t.string :published_lookup_key
      t.datetime :owner_consented_at
      t.string :provider_approval_reference
      t.timestamps
    end

    add_check_constraint :listening_profiles, "ownership_basis = 'administrative' AND btrim(ownership_reference) <> ''",
      name: "listening_profiles_administrative_ownership"
    add_check_constraint :listening_profiles, "provider_approval_reference IS NULL OR btrim(provider_approval_reference) <> ''",
      name: "listening_profiles_provider_reference"
  end
end
