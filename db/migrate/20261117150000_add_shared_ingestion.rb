class AddSharedIngestion < ActiveRecord::Migration[8.1]
  def up
    create_table :lastfm_accounts do |t|
      t.string :username, null: false
      t.string :lookup_key, null: false
      t.string :identity_key, null: false
      t.references :archive_user, null: false, foreign_key: { to_table: :users }
      t.string :state, null: false, default: "active"
      t.boolean :sync_enabled, null: false, default: false
      t.datetime :next_poll_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :dispatch_until
      t.datetime :last_poll_at
      t.datetime :last_successful_poll_at
      t.datetime :latest_scrobble_at
      t.bigint :synced_through
      t.integer :poll_interval, null: false, default: 45
      t.integer :failure_count, null: false, default: 0
      t.string :last_error
      t.timestamps
    end
    add_index :lastfm_accounts, :lookup_key, unique: true
    add_index :lastfm_accounts, :identity_key, unique: true
    add_index :lastfm_accounts, [ :next_poll_at, :id ], where: "sync_enabled AND state = 'active'", name: :due_lastfm_accounts
    add_check_constraint :lastfm_accounts, "state IN ('active','paused','conflict') AND poll_interval BETWEEN 30 AND 604800 AND failure_count >= 0 AND lookup_key = lower(username)", name: :valid_lastfm_schedule
    create_table :user_lastfm_accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :lastfm_account, null: false, foreign_key: true
      t.boolean :import_allowed, null: false, default: true
      t.boolean :interpretation_allowed, null: false, default: true
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :user_lastfm_accounts, [ :user_id, :lastfm_account_id ], unique: true
    create_table :lastfm_account_names do |t|
      t.references :lastfm_account, null: false, foreign_key: true
      t.string :lookup_key, null: false
      t.string :reason, null: false
      t.timestamps
    end
    add_index :lastfm_account_names, :lookup_key, unique: true
    add_reference :scrobbles, :lastfm_account, foreign_key: true
    add_reference :import_runs, :lastfm_account, foreign_key: true
    add_column :import_runs, :kind, :string, default: "historical", null: false
    add_column :import_runs, :lower_bound, :bigint
    add_column :import_runs, :actor_kind, :string, default: "legacy", null: false
    add_column :import_runs, :authorization_context, :jsonb, default: {}, null: false
    add_column :import_runs, :retry_count, :integer, default: 0, null: false
    add_column :import_runs, :retry_at, :datetime
    add_column :import_runs, :failure_kind, :string
    add_column :import_runs, :received_count, :bigint, default: 0, null: false
    add_column :import_runs, :repeated_count, :bigint, default: 0, null: false
    add_column :import_runs, :excluded_count, :bigint, default: 0, null: false
    add_column :import_runs, :boundary_done, :boolean, default: false, null: false
    add_column :import_runs, :boundary_second, :bigint
    add_column :import_runs, :boundary_page, :integer, default: 1, null: false
    add_column :import_runs, :boundary_total, :bigint
    create_table :source_fetches do |t|
      t.references :import_run, null: false, foreign_key: true
      t.references :lastfm_account, null: false, foreign_key: true
      t.references :legacy_import_page, foreign_key: { to_table: :import_pages }, index: { unique: true }
      t.integer :page_number, null: false
      t.bigint :lower_bound
      t.bigint :upper_bound, null: false
      t.string :phase, null: false, default: "main"
      t.jsonb :request_parameters, null: false, default: {}
      t.datetime :requested_at, null: false
      t.string :outcome, null: false
      t.binary :raw_body
      t.string :checksum
      t.string :error_class
      t.integer :retry_number, null: false, default: 0
      t.timestamps
    end
    create_table :page_commits do |t|
      t.references :source_fetch, null: false, foreign_key: true, index: { unique: true }
      t.references :import_page, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :counts, default: {}, null: false
      t.timestamps
    end
    create_table :source_deliveries do |t|
      t.references :source_fetch, null: false, foreign_key: true
      t.references :lastfm_account, null: false, foreign_key: true
      t.references :scrobble, foreign_key: true
      t.integer :position, null: false
      t.string :classification, null: false
      t.string :source_checksum, null: false
      t.timestamps
    end
    add_index :source_deliveries, [ :source_fetch_id, :position ], unique: true
    create_table :ingestion_issues do |t|
      t.references :lastfm_account, null: false, foreign_key: true
      t.references :import_run, foreign_key: true
      t.references :source_fetch, foreign_key: true
      t.string :kind, null: false
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
    create_table :ingestion_budgets do |t|
      t.string :name, null: false
      t.datetime :next_request_at, null: false
      t.timestamps
    end
    add_index :ingestion_budgets, :name, unique: true
    execute "INSERT INTO ingestion_budgets(name,next_request_at,created_at,updated_at) VALUES('lastfm',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)"
    # Map only exact existing usernames. Existing uniqueness forbids collisions.
    execute <<~SQL
      INSERT INTO lastfm_accounts(username,lookup_key,identity_key,archive_user_id,created_at,updated_at)
        SELECT lastfm_username,lower(lastfm_username),lower(lastfm_username),id,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP
        FROM users WHERE lastfm_username IS NOT NULL;
      INSERT INTO user_lastfm_accounts(user_id,lastfm_account_id,created_at,updated_at)
        SELECT archive_user_id,id,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP FROM lastfm_accounts;
      INSERT INTO lastfm_account_names(lastfm_account_id,lookup_key,reason,created_at,updated_at)
        SELECT id,lookup_key,'preserved P1.1 association; ownership unverified',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP FROM lastfm_accounts;
      UPDATE import_runs r SET lastfm_account_id=a.id FROM lastfm_accounts a WHERE r.user_id=a.archive_user_id;
    SQL
    # Source fields, payloads, IDs, timestamps, raw pages and checkpoints are untouched.
    cursor = 0
    loop do
      upper = select_value("SELECT max(id) FROM (SELECT id FROM scrobbles WHERE id > #{cursor} ORDER BY id LIMIT 1000) batch")
      break unless upper
      execute(<<~SQL)
        UPDATE scrobbles s SET lastfm_account_id=a.id FROM lastfm_accounts a
        WHERE s.user_id=a.archive_user_id AND s.id > #{cursor} AND s.id <= #{Integer(upper)}
      SQL
      cursor = Integer(upper)
    end
    # Completed legacy traversal is already audited; do not schedule a second backfill.
    execute <<~SQL
      UPDATE lastfm_accounts a SET
        latest_scrobble_at=(SELECT max(s.played_at) FROM scrobbles s WHERE s.lastfm_account_id=a.id),
        synced_through=(SELECT r.upper_bound FROM import_runs r WHERE r.lastfm_account_id=a.id AND r.status=2
          AND r.next_page > r.total_pages AND r.total_pages=(SELECT count(*) FROM import_pages p WHERE p.import_run_id=r.id)
          ORDER BY r.id DESC LIMIT 1),
        last_successful_poll_at=(SELECT max(r.last_success_at) FROM import_runs r WHERE r.lastfm_account_id=a.id AND r.status=2);
    SQL
    remove_index :users, name: :unique_normalized_lastfm_username
    remove_index :users, name: :index_users_on_lastfm_username
    add_check_constraint :import_runs, "kind IN ('historical','incremental','replay') AND actor_kind IN ('legacy','user','scheduler','operator') AND (lower_bound IS NULL OR lower_bound <= upper_bound)", name: :valid_ingestion_run
    # Include account identity once the one-time additive mapping has finished.
    execute <<~SQL
      CREATE OR REPLACE FUNCTION muzeum_preserve_source() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_OP IN ('DELETE','TRUNCATE') OR TG_TABLE_NAME <> 'scrobbles' THEN
          RAISE EXCEPTION 'Source evidence is immutable';
        END IF;
        IF ROW(NEW.user_id,NEW.played_at,NEW.payload,NEW.source_fingerprint,NEW.import_page_id,NEW.lastfm_account_id)
          IS DISTINCT FROM ROW(OLD.user_id,OLD.played_at,OLD.payload,OLD.source_fingerprint,OLD.import_page_id,OLD.lastfm_account_id) THEN
          RAISE EXCEPTION 'Source observation fields are immutable';
        END IF;
        RETURN NEW;
      END; $$;
    SQL
    %w[source_fetches source_deliveries ingestion_issues page_commits lastfm_account_names].each do |table|
      execute "CREATE TRIGGER retain_#{table} BEFORE UPDATE OR DELETE ON #{table} FOR EACH ROW EXECUTE FUNCTION muzeum_preserve_source()"
    end
    %w[scrobbles import_pages source_fetches source_deliveries ingestion_issues page_commits lastfm_account_names].each do |table|
      execute "CREATE TRIGGER retain_truncate_#{table} BEFORE TRUNCATE ON #{table} FOR EACH STATEMENT EXECUTE FUNCTION muzeum_preserve_source()"
    end
    execute <<~SQL
      CREATE FUNCTION muzeum_check_delivery_account() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM source_fetches f JOIN import_runs r ON r.id=f.import_run_id
          WHERE f.id=NEW.source_fetch_id AND f.lastfm_account_id=NEW.lastfm_account_id AND r.lastfm_account_id=NEW.lastfm_account_id)
          OR (NEW.scrobble_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM scrobbles s WHERE s.id=NEW.scrobble_id AND s.lastfm_account_id=NEW.lastfm_account_id)) THEN
          RAISE EXCEPTION 'Delivery account mismatch';
        END IF;
        RETURN NEW;
      END; $$;
      CREATE TRIGGER validate_delivery_account BEFORE INSERT ON source_deliveries FOR EACH ROW EXECUTE FUNCTION muzeum_check_delivery_account();
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Preserve shared archives and evidence; use reviewed compatible code rollback"
  end
end
