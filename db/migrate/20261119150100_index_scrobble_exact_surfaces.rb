class IndexScrobbleExactSurfaces < ActiveRecord::Migration[8.1]
  def change
    add_index :scrobbles,
      "lastfm_account_id, resolution_surface_key(payload->>'artist_name', payload->>'album_name', payload->>'track_name')",
      name: "index_scrobbles_on_archive_and_exact_surface"
  end
end
