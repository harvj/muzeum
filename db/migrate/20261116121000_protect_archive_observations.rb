class ProtectArchiveObservations < ActiveRecord::Migration[8.1]
  def up
    add_index :users, "lower(lastfm_username)", unique: true, name: "unique_normalized_lastfm_username"
    execute <<~SQL
      CREATE FUNCTION muzeum_preserve_source() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'Source observations are retained; explicit operator retention policy required';
        END IF;
        IF TG_TABLE_NAME = 'import_pages' THEN
          RAISE EXCEPTION 'Raw import pages are immutable';
        END IF;
        IF ROW(NEW.user_id, NEW.played_at, NEW.payload, NEW.source_fingerprint, NEW.import_page_id)
           IS DISTINCT FROM ROW(OLD.user_id, OLD.played_at, OLD.payload, OLD.source_fingerprint, OLD.import_page_id) THEN
          RAISE EXCEPTION 'Source observation fields are immutable';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER preserve_scrobble_source BEFORE UPDATE OR DELETE ON scrobbles
        FOR EACH ROW EXECUTE FUNCTION muzeum_preserve_source();
      CREATE TRIGGER preserve_raw_page BEFORE UPDATE OR DELETE ON import_pages
        FOR EACH ROW EXECUTE FUNCTION muzeum_preserve_source();
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Source protection requires explicit recovery review"
  end
end
