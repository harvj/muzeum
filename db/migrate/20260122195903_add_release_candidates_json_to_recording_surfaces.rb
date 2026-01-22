class AddReleaseCandidatesJsonToRecordingSurfaces < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_surfaces, :release_candidates, :jsonb, default: []
    add_column :recording_surfaces, :chosen_release_candidate_index, :integer

    rename_column :releases, :mbid, :ingested_from_release_mbid
    remove_column :releases, :primary_type, :string
    add_column :releases, :primary_type, :integer, null: false, default: 0
    add_column :releases, :secondary_type, :integer, null: false, default: 0
  end
end
