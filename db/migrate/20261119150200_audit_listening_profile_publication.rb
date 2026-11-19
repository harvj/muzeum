class AuditListeningProfilePublication < ActiveRecord::Migration[8.1]
  def up
    create_table :listening_profile_publication_events do |t|
      t.references :listening_profile, null: false, foreign_key: true
      t.string :action, null: false
      t.text :evidence_reference
      t.datetime :created_at, null: false
      t.check_constraint <<~SQL.squish, name: "listening_profile_publication_event_evidence"
        (action = 'grant_revoked' AND evidence_reference IS NULL) OR
        (action IN ('consented', 'activated', 'withdrawn') AND
          evidence_reference IS NOT NULL AND btrim(evidence_reference) <> '')
      SQL
    end

    execute <<~SQL
      CREATE TRIGGER retain_listening_profile_publication_events
        BEFORE UPDATE OR DELETE ON listening_profile_publication_events
        FOR EACH ROW EXECUTE FUNCTION muzeum_preserve_source();

      CREATE FUNCTION withdraw_profile_on_grant_loss() RETURNS trigger
        LANGUAGE plpgsql AS $$
      DECLARE
        profile_id bigint;
      BEGIN
        IF OLD.revoked_at IS NOT NULL THEN RETURN NULL; END IF;
        IF TG_OP = 'UPDATE' THEN
          IF NEW.revoked_at IS NULL AND NEW.user_id = OLD.user_id
              AND NEW.lastfm_account_id = OLD.lastfm_account_id THEN RETURN NULL; END IF;
        END IF;

        -- Lock even a private profile so concurrent activation cannot escape withdrawal.
        SELECT id INTO profile_id FROM public.listening_profiles
          WHERE lastfm_account_id = OLD.lastfm_account_id AND owner_id = OLD.user_id
          FOR UPDATE;
        UPDATE public.listening_profiles
          SET published_lookup_key = NULL, provider_approval_reference = NULL,
              updated_at = statement_timestamp()
          WHERE id = profile_id AND published_lookup_key IS NOT NULL;
        IF FOUND THEN
          INSERT INTO public.listening_profile_publication_events
            (listening_profile_id, action, created_at)
            VALUES (profile_id, 'grant_revoked', statement_timestamp());
        END IF;
        RETURN NULL;
      END;
      $$;

      CREATE TRIGGER withdraw_profile_on_grant_loss
        AFTER UPDATE OF revoked_at, user_id, lastfm_account_id OR DELETE ON user_lastfm_accounts
        FOR EACH ROW EXECUTE FUNCTION withdraw_profile_on_grant_loss();
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Preserve the publication audit history"
  end
end
