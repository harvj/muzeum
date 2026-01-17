class AddRecordingToScrobbles < ActiveRecord::Migration[8.1]
  def change
    add_reference :scrobbles, :recording, null: true, foreign_key: true
  end
end
