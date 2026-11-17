class EnforceIngestionLineage < ActiveRecord::Migration[8.1]
  def up
    change_column_null :scrobbles, :lastfm_account_id, false
    change_column_null :import_runs, :lastfm_account_id, false
    add_check_constraint :source_fetches, "raw_body IS NULL OR checksum = encode(sha256(raw_body), 'hex')", name: :verified_source_fetch_checksum
    add_check_constraint :source_deliveries, "position > 0 AND classification IN ('inserted','repeat','metadata_changed','legacy_first','now_playing','undated','malformed','outside_window')", name: :valid_source_delivery
    add_check_constraint :source_fetches, "page_number > 0 AND phase IN ('main','boundary') AND (raw_body IS NULL OR checksum IS NOT NULL)", name: :valid_source_fetch
    execute <<~SQL
      CREATE FUNCTION muzeum_preserve_ingestion_identity() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_TABLE_NAME = 'lastfm_accounts' THEN
          IF ROW(NEW.id,NEW.identity_key,NEW.archive_user_id) IS DISTINCT FROM ROW(OLD.id,OLD.identity_key,OLD.archive_user_id) THEN
            RAISE EXCEPTION 'Source account identity is immutable';
          END IF;
        ELSIF ROW(NEW.id,NEW.user_id,NEW.lastfm_account_id,NEW.source_username,NEW.lower_bound,NEW.upper_bound,NEW.kind,NEW.actor_kind,NEW.authorization_context)
          IS DISTINCT FROM ROW(OLD.id,OLD.user_id,OLD.lastfm_account_id,OLD.source_username,OLD.lower_bound,OLD.upper_bound,OLD.kind,OLD.actor_kind,OLD.authorization_context) THEN
          RAISE EXCEPTION 'Import origin and authorization evidence are immutable';
        END IF;
        RETURN NEW;
      END; $$;
      CREATE TRIGGER preserve_source_account_identity BEFORE UPDATE ON lastfm_accounts FOR EACH ROW EXECUTE FUNCTION muzeum_preserve_ingestion_identity();
      CREATE TRIGGER preserve_run_origin BEFORE UPDATE ON import_runs FOR EACH ROW EXECUTE FUNCTION muzeum_preserve_ingestion_identity();
      CREATE FUNCTION muzeum_preserve_scrobble_identifier() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF ROW(NEW.id,NEW.created_at) IS DISTINCT FROM ROW(OLD.id,OLD.created_at) THEN
          RAISE EXCEPTION 'Source identifier and recorded timestamp are immutable';
        END IF;
        RETURN NEW;
      END; $$;
      CREATE TRIGGER preserve_scrobble_identifier BEFORE UPDATE ON scrobbles FOR EACH ROW EXECUTE FUNCTION muzeum_preserve_scrobble_identifier();
      CREATE FUNCTION muzeum_validate_page_commit() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NOT EXISTS(SELECT 1 FROM source_fetches f JOIN import_pages p ON p.import_run_id=f.import_run_id
          WHERE f.id=NEW.source_fetch_id AND p.id=NEW.import_page_id AND p.checksum=f.checksum) THEN
          RAISE EXCEPTION 'Page commit evidence mismatch';
        END IF;
        RETURN NEW;
      END; $$;
      CREATE TRIGGER validate_page_commit BEFORE INSERT ON page_commits FOR EACH ROW EXECUTE FUNCTION muzeum_validate_page_commit();
    SQL
  end
  def down
    raise ActiveRecord::IrreversibleMigration, "Retain source identity protections"
  end
end
