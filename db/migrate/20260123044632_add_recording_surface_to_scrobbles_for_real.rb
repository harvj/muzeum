class AddRecordingSurfaceToScrobblesForReal < ActiveRecord::Migration[8.1]
  def change
    add_reference :scrobbles, :recording_surface, null: true, foreign_key: true
  end
end
