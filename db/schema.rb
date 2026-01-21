# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_01_21_151132) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "artists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "mbid"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["mbid"], name: "index_artists_on_mbid", unique: true
    t.index ["name"], name: "index_artists_on_name"
  end

  create_table "daily_listens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.integer "listen_count", default: 0, null: false
    t.bigint "recording_id", null: false
    t.bigint "total_duration_ms", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "year", limit: 2, null: false
    t.index ["recording_id"], name: "index_daily_listens_on_recording_id"
    t.index ["user_id", "date"], name: "index_daily_listens_on_user_id_and_date"
    t.index ["user_id", "recording_id", "date"], name: "index_daily_listens_on_user_id_and_recording_id_and_date", unique: true
    t.index ["user_id", "recording_id"], name: "index_daily_listens_on_user_id_and_recording_id"
    t.index ["user_id"], name: "index_daily_listens_on_user_id"
    t.index ["year"], name: "index_daily_listens_on_year"
  end

  create_table "import_runs", force: :cascade do |t|
    t.integer "artists_created"
    t.datetime "created_at", null: false
    t.jsonb "notes"
    t.datetime "range_end_at"
    t.datetime "range_start_at"
    t.integer "recordings_created"
    t.integer "scrobbles_processed"
    t.integer "status", default: 0, null: false
    t.integer "unmapped_recordings"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["created_at"], name: "index_import_runs_on_created_at"
    t.index ["range_end_at"], name: "index_import_runs_on_range_end_at"
    t.index ["user_id", "range_start_at", "range_end_at"], name: "index_import_runs_on_user_and_range"
    t.index ["user_id"], name: "index_import_runs_on_user_id"
  end

  create_table "recording_artists", force: :cascade do |t|
    t.bigint "artist_id", null: false
    t.datetime "created_at", null: false
    t.integer "position"
    t.bigint "recording_id", null: false
    t.string "role", default: "primary", null: false
    t.datetime "updated_at", null: false
    t.float "weight", default: 1.0, null: false
    t.index ["artist_id"], name: "index_recording_artists_on_artist_id"
    t.index ["recording_id", "artist_id"], name: "index_recording_artists_on_recording_id_and_artist_id", unique: true
    t.index ["recording_id"], name: "index_recording_artists_on_recording_id"
  end

  create_table "recording_surfaces", force: :cascade do |t|
    t.string "album_mbid"
    t.string "album_name"
    t.string "artist_mbid"
    t.string "artist_name", null: false
    t.float "confidence", default: 0.5, null: false
    t.datetime "created_at", null: false
    t.string "normalized_key", null: false
    t.integer "observed_count", default: 1, null: false
    t.bigint "recording_id", null: false
    t.string "source", default: "lastfm", null: false
    t.string "track_mbid"
    t.string "track_name", null: false
    t.datetime "updated_at", null: false
    t.index ["artist_mbid"], name: "index_recording_surfaces_on_artist_mbid"
    t.index ["normalized_key"], name: "index_recording_surfaces_on_normalized_key", unique: true
    t.index ["recording_id"], name: "index_recording_surfaces_on_recording_id"
    t.index ["track_mbid"], name: "index_recording_surfaces_on_track_mbid"
  end

  create_table "recordings", force: :cascade do |t|
    t.float "confidence", default: 0.0, null: false
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "mbid"
    t.bigint "merged_into_id"
    t.string "source", default: "lastfm", null: false
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["mbid"], name: "index_recordings_on_mbid", unique: true
    t.index ["merged_into_id"], name: "index_recordings_on_merged_into_id"
    t.index ["title"], name: "index_recordings_on_title"
  end

  create_table "release_artists", force: :cascade do |t|
    t.bigint "artist_id", null: false
    t.datetime "created_at", null: false
    t.integer "position"
    t.bigint "release_id", null: false
    t.datetime "updated_at", null: false
    t.index ["artist_id"], name: "index_release_artists_on_artist_id"
    t.index ["release_id", "artist_id"], name: "index_release_artists_on_release_id_and_artist_id", unique: true
    t.index ["release_id"], name: "index_release_artists_on_release_id"
  end

  create_table "release_recordings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position", null: false
    t.bigint "recording_id", null: false
    t.bigint "release_id", null: false
    t.datetime "updated_at", null: false
    t.index ["recording_id"], name: "index_release_recordings_on_recording_id"
    t.index ["release_id", "position"], name: "index_release_recordings_on_release_id_and_position", unique: true
    t.index ["release_id", "recording_id"], name: "index_release_recordings_on_release_id_and_recording_id", unique: true
    t.index ["release_id"], name: "index_release_recordings_on_release_id"
  end

  create_table "releases", force: :cascade do |t|
    t.string "mbid"
    t.string "primary_type"
    t.integer "release_day"
    t.string "release_group_mbid"
    t.integer "release_month"
    t.integer "release_year"
    t.string "source", default: "musicbrainz", null: false
    t.string "title", null: false
    t.index ["mbid"], name: "index_releases_on_mbid", unique: true
    t.index ["release_group_mbid"], name: "index_releases_on_release_group_mbid"
  end

  create_table "scrobbles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "payload", null: false
    t.datetime "played_at", null: false
    t.bigint "recording_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["played_at"], name: "index_scrobbles_on_played_at"
    t.index ["recording_id"], name: "index_scrobbles_on_recording_id"
    t.index ["user_id", "played_at"], name: "index_scrobbles_on_user_and_played_at", unique: true
    t.index ["user_id"], name: "index_scrobbles_on_user_id"
  end

  create_table "user_timezones", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "effective_from", null: false
    t.string "timezone", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_user_timezones_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "lastfm_username", null: false
    t.datetime "updated_at", null: false
    t.index ["lastfm_username"], name: "index_users_on_lastfm_username", unique: true
  end

  add_foreign_key "daily_listens", "recordings"
  add_foreign_key "daily_listens", "users"
  add_foreign_key "import_runs", "users"
  add_foreign_key "recording_artists", "artists"
  add_foreign_key "recording_artists", "recordings"
  add_foreign_key "recording_surfaces", "recordings"
  add_foreign_key "release_artists", "artists"
  add_foreign_key "release_artists", "releases"
  add_foreign_key "release_recordings", "recordings"
  add_foreign_key "release_recordings", "releases"
  add_foreign_key "scrobbles", "recordings"
end
