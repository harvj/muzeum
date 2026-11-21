class IndexResolutionDecisionsByRecording < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :resolution_decisions, [ :recording_id, :user_id ], where: "recording_id IS NOT NULL",
      name: "index_resolution_decisions_on_recording_and_listener", algorithm: :concurrently
  end
end
