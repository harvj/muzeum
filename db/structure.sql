SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: muzeum_check_delivery_account(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.muzeum_check_delivery_account() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM source_fetches f JOIN import_runs r ON r.id=f.import_run_id
    WHERE f.id=NEW.source_fetch_id AND f.lastfm_account_id=NEW.lastfm_account_id AND r.lastfm_account_id=NEW.lastfm_account_id)
    OR (NEW.scrobble_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM scrobbles s WHERE s.id=NEW.scrobble_id AND s.lastfm_account_id=NEW.lastfm_account_id)) THEN
    RAISE EXCEPTION 'Delivery account mismatch';
  END IF;
  RETURN NEW;
END; $$;


--
-- Name: muzeum_preserve_ingestion_identity(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.muzeum_preserve_ingestion_identity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: muzeum_preserve_scrobble_identifier(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.muzeum_preserve_scrobble_identifier() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF ROW(NEW.id,NEW.created_at) IS DISTINCT FROM ROW(OLD.id,OLD.created_at) THEN
    RAISE EXCEPTION 'Source identifier and recorded timestamp are immutable';
  END IF;
  RETURN NEW;
END; $$;


--
-- Name: muzeum_preserve_source(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.muzeum_preserve_source() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: muzeum_validate_page_commit(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.muzeum_validate_page_commit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM source_fetches f JOIN import_pages p ON p.import_run_id=f.import_run_id
    WHERE f.id=NEW.source_fetch_id AND p.id=NEW.import_page_id AND p.checksum=f.checksum) THEN
    RAISE EXCEPTION 'Page commit evidence mismatch';
  END IF;
  RETURN NEW;
END; $$;


--
-- Name: resolution_check_decision(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.resolution_check_decision() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE prior bigint;
BEGIN
  SELECT id INTO prior FROM resolution_decisions
    WHERE surface_id = NEW.surface_id AND user_id IS NOT DISTINCT FROM NEW.user_id
      AND scrobble_id IS NOT DISTINCT FROM NEW.scrobble_id ORDER BY id DESC LIMIT 1;
  IF prior IS DISTINCT FROM NEW.predecessor_id THEN
    RAISE EXCEPTION 'Resolution predecessor must be the current head of the same stream';
  END IF;
  IF NEW.scrobble_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM resolution_memberships WHERE scrobble_id = NEW.scrobble_id AND surface_id = NEW.surface_id
  ) THEN RAISE EXCEPTION 'Decision must match the observation surface'; END IF;
  IF NEW.assessment_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM resolution_assessments a JOIN resolution_groups g ON g.id = a.group_id
    WHERE a.id = NEW.assessment_id AND g.surface_id = NEW.surface_id
  ) THEN RAISE EXCEPTION 'Decision assessment must match the surface'; END IF;
  IF NEW.user_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM resolution_surfaces s JOIN user_lastfm_accounts m USING (lastfm_account_id)
    WHERE s.id = NEW.surface_id AND m.user_id = NEW.user_id AND m.revoked_at IS NULL
  ) THEN RAISE EXCEPTION 'Decision requires an active archive grant'; END IF;
  RETURN NEW;
END;
$$;


--
-- Name: resolution_check_membership(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.resolution_check_membership() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM scrobbles o JOIN resolution_surfaces s ON s.id = NEW.surface_id
    WHERE o.id = NEW.scrobble_id AND o.lastfm_account_id = s.lastfm_account_id
      AND (o.payload->>'artist_name', o.payload->>'album_name', o.payload->>'track_name')
          IS NOT DISTINCT FROM (s.artist, s.album, s.track)
  ) THEN RAISE EXCEPTION 'Resolution membership must match the source tuple and archive'; END IF;
  RETURN NEW;
END;
$$;


--
-- Name: resolution_check_work(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.resolution_check_work() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM 1 FROM resolution_pilots WHERE id = NEW.pilot_id FOR UPDATE;
    IF (SELECT count(*) FROM resolution_work WHERE pilot_id = NEW.pilot_id) >= 100 THEN
      RAISE EXCEPTION 'Resolution pilot group limit reached';
    END IF;
  ELSE
    IF (OLD.pilot_id, OLD.group_id) IS DISTINCT FROM (NEW.pilot_id, NEW.group_id) THEN
      RAISE EXCEPTION 'Resolution work scope is immutable';
    END IF;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM resolution_pilots p JOIN resolution_surfaces s USING (lastfm_account_id)
    JOIN resolution_groups g ON g.surface_id = s.id
    WHERE p.id = NEW.pilot_id AND g.id = NEW.group_id
  ) THEN RAISE EXCEPTION 'Resolution work must match the pilot archive'; END IF;
  IF NEW.assessment_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM resolution_assessments WHERE id = NEW.assessment_id AND group_id = NEW.group_id
  ) THEN RAISE EXCEPTION 'Resolution work assessment must match its group'; END IF;
  RETURN NEW;
END;
$$;


--
-- Name: resolution_keep_pilot_bounds(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.resolution_keep_pilot_bounds() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (OLD.lastfm_account_id, OLD.upper_id, OLD.live) IS DISTINCT FROM
     (NEW.lastfm_account_id, NEW.upper_id, NEW.live) THEN
    RAISE EXCEPTION 'Resolution pilot bounds are immutable';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: resolution_surface_key(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.resolution_surface_key(artist text, album text, track text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT encode(sha256(convert_to(jsonb_build_array(artist, album, track)::text, 'UTF8')), 'hex')
$$;


--
-- Name: withdraw_profile_on_grant_loss(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.withdraw_profile_on_grant_loss() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: artists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.artists (
    id bigint NOT NULL,
    name character varying NOT NULL,
    mbid character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    country character varying
);


--
-- Name: artists_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.artists_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: artists_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.artists_id_seq OWNED BY public.artists.id;


--
-- Name: catalog_imports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.catalog_imports (
    id bigint NOT NULL,
    kind character varying NOT NULL,
    entity_id bigint NOT NULL,
    context jsonb DEFAULT '{}'::jsonb NOT NULL,
    state character varying DEFAULT 'pending'::character varying NOT NULL,
    due_at timestamp(6) without time zone NOT NULL,
    lease_until timestamp(6) without time zone,
    lease_token character varying,
    attempts integer DEFAULT 0 NOT NULL,
    request_count integer DEFAULT 0 NOT NULL,
    failure character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT catalog_import_lease CHECK ((((state)::text = 'refreshing'::text) = ((lease_token IS NOT NULL) AND (lease_until IS NOT NULL)))),
    CONSTRAINT catalog_import_state CHECK (((state)::text = ANY ((ARRAY['pending'::character varying, 'refreshing'::character varying, 'imported'::character varying, 'incomplete'::character varying, 'failed'::character varying])::text[])))
);


--
-- Name: catalog_imports_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.catalog_imports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: catalog_imports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.catalog_imports_id_seq OWNED BY public.catalog_imports.id;


--
-- Name: catalog_revisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.catalog_revisions (
    id bigint NOT NULL,
    catalog_import_id bigint NOT NULL,
    entity_type character varying NOT NULL,
    entity_id bigint NOT NULL,
    evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: catalog_revisions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.catalog_revisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: catalog_revisions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.catalog_revisions_id_seq OWNED BY public.catalog_revisions.id;


--
-- Name: catalog_track_slots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.catalog_track_slots (
    id bigint NOT NULL,
    release_id bigint NOT NULL,
    recording_id bigint NOT NULL,
    medium integer NOT NULL,
    "position" integer NOT NULL,
    number character varying,
    track_mbid character varying NOT NULL,
    title character varying NOT NULL,
    edition_mbid character varying,
    appearance_date character varying,
    source_recording_mbid character varying,
    duration_ms integer,
    source_artist_credit jsonb,
    CONSTRAINT catalog_track_slot_position CHECK (((medium > 0) AND ("position" > 0)))
);


--
-- Name: catalog_track_slots_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.catalog_track_slots_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: catalog_track_slots_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.catalog_track_slots_id_seq OWNED BY public.catalog_track_slots.id;


--
-- Name: daily_listens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.daily_listens (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    recording_id bigint NOT NULL,
    date date NOT NULL,
    listen_count integer DEFAULT 0 NOT NULL,
    total_duration_ms bigint DEFAULT 0 NOT NULL,
    year smallint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: daily_listens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.daily_listens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: daily_listens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.daily_listens_id_seq OWNED BY public.daily_listens.id;


--
-- Name: import_pages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_pages (
    id bigint NOT NULL,
    import_run_id bigint NOT NULL,
    number integer NOT NULL,
    raw_body text NOT NULL,
    checksum character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: import_pages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.import_pages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: import_pages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.import_pages_id_seq OWNED BY public.import_pages.id;


--
-- Name: import_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_runs (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    scrobbles_processed integer,
    recordings_created integer,
    artists_created integer,
    unmapped_recordings integer,
    notes jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    range_start_at timestamp(6) without time zone,
    range_end_at timestamp(6) without time zone,
    status integer DEFAULT 0 NOT NULL,
    next_page integer DEFAULT 1 NOT NULL,
    upper_bound bigint,
    total_pages integer,
    expected_count bigint,
    last_error character varying,
    last_success_at timestamp(6) without time zone,
    source_username character varying,
    lastfm_account_id bigint NOT NULL,
    kind character varying DEFAULT 'historical'::character varying NOT NULL,
    lower_bound bigint,
    actor_kind character varying DEFAULT 'legacy'::character varying NOT NULL,
    authorization_context jsonb DEFAULT '{}'::jsonb NOT NULL,
    retry_count integer DEFAULT 0 NOT NULL,
    retry_at timestamp(6) without time zone,
    failure_kind character varying,
    received_count bigint DEFAULT 0 NOT NULL,
    repeated_count bigint DEFAULT 0 NOT NULL,
    excluded_count bigint DEFAULT 0 NOT NULL,
    boundary_done boolean DEFAULT false NOT NULL,
    boundary_second bigint,
    boundary_page integer DEFAULT 1 NOT NULL,
    boundary_total bigint,
    CONSTRAINT valid_ingestion_run CHECK ((((kind)::text = ANY ((ARRAY['historical'::character varying, 'incremental'::character varying, 'replay'::character varying])::text[])) AND ((actor_kind)::text = ANY ((ARRAY['legacy'::character varying, 'user'::character varying, 'scheduler'::character varying, 'operator'::character varying])::text[])) AND ((lower_bound IS NULL) OR (lower_bound <= upper_bound))))
);


--
-- Name: import_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.import_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: import_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.import_runs_id_seq OWNED BY public.import_runs.id;


--
-- Name: ingestion_budgets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingestion_budgets (
    id bigint NOT NULL,
    name character varying NOT NULL,
    next_request_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ingestion_budgets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ingestion_budgets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ingestion_budgets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ingestion_budgets_id_seq OWNED BY public.ingestion_budgets.id;


--
-- Name: ingestion_issues; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingestion_issues (
    id bigint NOT NULL,
    lastfm_account_id bigint NOT NULL,
    import_run_id bigint,
    source_fetch_id bigint,
    kind character varying NOT NULL,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ingestion_issues_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ingestion_issues_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ingestion_issues_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ingestion_issues_id_seq OWNED BY public.ingestion_issues.id;


--
-- Name: lastfm_account_names; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lastfm_account_names (
    id bigint NOT NULL,
    lastfm_account_id bigint NOT NULL,
    lookup_key character varying NOT NULL,
    reason character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: lastfm_account_names_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.lastfm_account_names_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lastfm_account_names_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.lastfm_account_names_id_seq OWNED BY public.lastfm_account_names.id;


--
-- Name: lastfm_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lastfm_accounts (
    id bigint NOT NULL,
    username character varying NOT NULL,
    lookup_key character varying NOT NULL,
    identity_key character varying NOT NULL,
    archive_user_id bigint NOT NULL,
    state character varying DEFAULT 'active'::character varying NOT NULL,
    sync_enabled boolean DEFAULT false NOT NULL,
    next_poll_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    dispatch_until timestamp(6) without time zone,
    last_poll_at timestamp(6) without time zone,
    last_successful_poll_at timestamp(6) without time zone,
    latest_scrobble_at timestamp(6) without time zone,
    synced_through bigint,
    poll_interval integer DEFAULT 45 NOT NULL,
    failure_count integer DEFAULT 0 NOT NULL,
    last_error character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT valid_lastfm_schedule CHECK ((((state)::text = ANY ((ARRAY['active'::character varying, 'paused'::character varying, 'conflict'::character varying])::text[])) AND ((poll_interval >= 30) AND (poll_interval <= 604800)) AND (failure_count >= 0) AND ((lookup_key)::text = lower((username)::text))))
);


--
-- Name: lastfm_accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.lastfm_accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lastfm_accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.lastfm_accounts_id_seq OWNED BY public.lastfm_accounts.id;


--
-- Name: listening_profile_publication_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.listening_profile_publication_events (
    id bigint NOT NULL,
    listening_profile_id bigint NOT NULL,
    action character varying NOT NULL,
    evidence_reference text,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT listening_profile_publication_event_evidence CHECK (((((action)::text = 'grant_revoked'::text) AND (evidence_reference IS NULL)) OR (((action)::text = ANY ((ARRAY['consented'::character varying, 'activated'::character varying, 'withdrawn'::character varying])::text[])) AND (evidence_reference IS NOT NULL) AND (btrim(evidence_reference) <> ''::text))))
);


--
-- Name: listening_profile_publication_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.listening_profile_publication_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: listening_profile_publication_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.listening_profile_publication_events_id_seq OWNED BY public.listening_profile_publication_events.id;


--
-- Name: listening_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.listening_profiles (
    id bigint NOT NULL,
    lastfm_account_id bigint NOT NULL,
    owner_id bigint NOT NULL,
    ownership_basis character varying NOT NULL,
    ownership_reference text NOT NULL,
    published_lookup_key character varying,
    owner_consented_at timestamp(6) without time zone,
    provider_approval_reference character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT listening_profiles_administrative_ownership CHECK ((((ownership_basis)::text = 'administrative'::text) AND (btrim(ownership_reference) <> ''::text))),
    CONSTRAINT listening_profiles_provider_reference CHECK (((provider_approval_reference IS NULL) OR (btrim((provider_approval_reference)::text) <> ''::text)))
);


--
-- Name: listening_profiles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.listening_profiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: listening_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.listening_profiles_id_seq OWNED BY public.listening_profiles.id;


--
-- Name: musical_identity_decisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.musical_identity_decisions (
    id bigint NOT NULL,
    entity_type character varying NOT NULL,
    entity_id bigint NOT NULL,
    user_id bigint NOT NULL,
    colors character varying[] DEFAULT '{}'::character varying[] NOT NULL,
    rationale text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: musical_identity_decisions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.musical_identity_decisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: musical_identity_decisions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.musical_identity_decisions_id_seq OWNED BY public.musical_identity_decisions.id;


--
-- Name: oidc_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oidc_attempts (
    id bigint NOT NULL,
    state character varying NOT NULL,
    browser_digest character varying NOT NULL,
    nonce character varying NOT NULL,
    verifier character varying NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL
);


--
-- Name: oidc_attempts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oidc_attempts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oidc_attempts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oidc_attempts_id_seq OWNED BY public.oidc_attempts.id;


--
-- Name: page_commits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.page_commits (
    id bigint NOT NULL,
    source_fetch_id bigint NOT NULL,
    import_page_id bigint NOT NULL,
    counts jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: page_commits_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.page_commits_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: page_commits_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.page_commits_id_seq OWNED BY public.page_commits.id;


--
-- Name: recording_artists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recording_artists (
    id bigint NOT NULL,
    recording_id bigint NOT NULL,
    artist_id bigint NOT NULL,
    "position" integer,
    weight double precision DEFAULT 1.0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    role integer DEFAULT 0 NOT NULL
);


--
-- Name: recording_artists_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.recording_artists_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: recording_artists_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.recording_artists_id_seq OWNED BY public.recording_artists.id;


--
-- Name: recording_source_decisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recording_source_decisions (
    id bigint NOT NULL,
    source_mbid uuid NOT NULL,
    recording_id bigint NOT NULL,
    actor character varying NOT NULL,
    evidence jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: recording_source_decisions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.recording_source_decisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: recording_source_decisions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.recording_source_decisions_id_seq OWNED BY public.recording_source_decisions.id;


--
-- Name: recording_surfaces; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recording_surfaces (
    id bigint NOT NULL,
    recording_id bigint,
    artist_name character varying NOT NULL,
    track_name character varying NOT NULL,
    album_name character varying,
    artist_mbid character varying,
    track_mbid character varying,
    album_mbid character varying,
    normalized_key character varying NOT NULL,
    observed_count integer DEFAULT 1 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    release_candidates jsonb DEFAULT '[]'::jsonb,
    chosen_release_candidate_index integer,
    ingested_release_id bigint,
    ingest_log jsonb DEFAULT '[]'::jsonb NOT NULL
);


--
-- Name: recording_surfaces_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.recording_surfaces_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: recording_surfaces_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.recording_surfaces_id_seq OWNED BY public.recording_surfaces.id;


--
-- Name: recordings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recordings (
    id bigint NOT NULL,
    title character varying NOT NULL,
    duration_ms integer,
    mbid character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: recordings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.recordings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: recordings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.recordings_id_seq OWNED BY public.recordings.id;


--
-- Name: release_artists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.release_artists (
    id bigint NOT NULL,
    release_id bigint NOT NULL,
    artist_id bigint NOT NULL,
    "position" integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: release_artists_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.release_artists_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: release_artists_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.release_artists_id_seq OWNED BY public.release_artists.id;


--
-- Name: release_ranking_decisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.release_ranking_decisions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    release_id bigint NOT NULL,
    included boolean NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: release_ranking_decisions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.release_ranking_decisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: release_ranking_decisions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.release_ranking_decisions_id_seq OWNED BY public.release_ranking_decisions.id;


--
-- Name: release_recordings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.release_recordings (
    id bigint NOT NULL,
    release_id bigint NOT NULL,
    recording_id bigint NOT NULL,
    "position" integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: release_recordings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.release_recordings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: release_recordings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.release_recordings_id_seq OWNED BY public.release_recordings.id;


--
-- Name: release_track_listening_decisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.release_track_listening_decisions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    release_id bigint NOT NULL,
    recording_id bigint NOT NULL,
    included boolean NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: release_track_listening_decisions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.release_track_listening_decisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: release_track_listening_decisions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.release_track_listening_decisions_id_seq OWNED BY public.release_track_listening_decisions.id;


--
-- Name: releases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.releases (
    id bigint NOT NULL,
    title character varying NOT NULL,
    ingested_from_release_mbid character varying,
    release_group_mbid character varying,
    release_year integer,
    release_month integer,
    release_day integer,
    source character varying DEFAULT 'musicbrainz'::character varying NOT NULL,
    primary_type integer DEFAULT 0 NOT NULL,
    secondary_type integer DEFAULT 0 NOT NULL,
    catalog_country character varying,
    catalog_verified_at timestamp(6) without time zone
);


--
-- Name: releases_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.releases_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: releases_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.releases_id_seq OWNED BY public.releases.id;


--
-- Name: resolution_assessments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.resolution_assessments (
    id bigint NOT NULL,
    group_id bigint NOT NULL,
    version text NOT NULL,
    actor text NOT NULL,
    digest text NOT NULL,
    evidence jsonb NOT NULL,
    suggested_recording_id bigint,
    created_at timestamp without time zone NOT NULL
);


--
-- Name: resolution_assessments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.resolution_assessments ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.resolution_assessments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: resolution_decisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.resolution_decisions (
    id bigint NOT NULL,
    surface_id bigint NOT NULL,
    user_id bigint,
    scrobble_id bigint,
    recording_id bigint,
    assessment_id bigint,
    predecessor_id bigint,
    actor text NOT NULL,
    reason text NOT NULL,
    version text NOT NULL,
    evidence jsonb NOT NULL,
    mode text NOT NULL,
    created_at timestamp without time zone NOT NULL,
    CONSTRAINT resolution_decisions_actor_check CHECK ((actor <> ''::text)),
    CONSTRAINT resolution_decisions_check CHECK (((mode = 'resolved'::text) = (recording_id IS NOT NULL))),
    CONSTRAINT resolution_decisions_check1 CHECK (((user_id IS NOT NULL) OR ((scrobble_id IS NULL) AND (mode <> 'inherit'::text) AND (assessment_id IS NOT NULL)))),
    CONSTRAINT resolution_decisions_mode_check CHECK ((mode = ANY (ARRAY['resolved'::text, 'unresolved'::text, 'inherit'::text]))),
    CONSTRAINT resolution_decisions_reason_check CHECK ((reason <> ''::text)),
    CONSTRAINT resolution_decisions_version_check CHECK ((version <> ''::text))
);


--
-- Name: resolution_decisions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.resolution_decisions ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.resolution_decisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: resolution_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.resolution_groups (
    id bigint NOT NULL,
    surface_id bigint NOT NULL,
    version text NOT NULL,
    claims jsonb NOT NULL
);


--
-- Name: resolution_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.resolution_groups ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.resolution_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: resolution_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.resolution_memberships (
    scrobble_id bigint NOT NULL,
    surface_id bigint NOT NULL
);


--
-- Name: resolution_pilots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.resolution_pilots (
    id bigint NOT NULL,
    lastfm_account_id bigint NOT NULL,
    upper_id bigint NOT NULL,
    cursor bigint DEFAULT 0 NOT NULL,
    observations_selected integer DEFAULT 0 NOT NULL,
    selection_finished boolean DEFAULT false NOT NULL,
    live boolean NOT NULL,
    musicbrainz_requests integer DEFAULT 0 NOT NULL,
    discogs_requests integer DEFAULT 0 NOT NULL,
    CONSTRAINT resolution_pilots_check CHECK (((cursor >= 0) AND (cursor <= upper_id))),
    CONSTRAINT resolution_pilots_discogs_requests_check CHECK (((discogs_requests >= 0) AND (discogs_requests <= 150))),
    CONSTRAINT resolution_pilots_musicbrainz_requests_check CHECK (((musicbrainz_requests >= 0) AND (musicbrainz_requests <= 300))),
    CONSTRAINT resolution_pilots_observations_selected_check CHECK (((observations_selected >= 0) AND (observations_selected <= 1000))),
    CONSTRAINT resolution_pilots_upper_id_check CHECK ((upper_id > 0))
);


--
-- Name: resolution_pilots_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.resolution_pilots ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.resolution_pilots_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: resolution_provider_budgets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.resolution_provider_budgets (
    provider text NOT NULL,
    available_at timestamp without time zone NOT NULL
);


--
-- Name: resolution_request_cache; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.resolution_request_cache (
    request_key text NOT NULL,
    expires_at timestamp without time zone NOT NULL,
    document jsonb NOT NULL
);


--
-- Name: resolution_surfaces; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.resolution_surfaces (
    id bigint NOT NULL,
    lastfm_account_id bigint NOT NULL,
    artist text,
    album text,
    track text,
    exact_key text GENERATED ALWAYS AS (public.resolution_surface_key(artist, album, track)) STORED
);


--
-- Name: resolution_surfaces_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.resolution_surfaces ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.resolution_surfaces_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: resolution_work; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.resolution_work (
    id bigint NOT NULL,
    pilot_id bigint NOT NULL,
    group_id bigint NOT NULL,
    state text DEFAULT 'pending'::text NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    due_at timestamp without time zone NOT NULL,
    lease_token uuid,
    lease_until timestamp without time zone,
    failure text,
    assessment_id bigint,
    CONSTRAINT resolution_work_attempts_check CHECK ((attempts >= 0)),
    CONSTRAINT resolution_work_check CHECK (((state = 'leased'::text) = ((lease_token IS NOT NULL) AND (lease_until IS NOT NULL)))),
    CONSTRAINT resolution_work_check1 CHECK (((state = 'done'::text) = (assessment_id IS NOT NULL))),
    CONSTRAINT resolution_work_state_check CHECK ((state = ANY (ARRAY['pending'::text, 'leased'::text, 'done'::text, 'failed'::text])))
);


--
-- Name: resolution_work_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.resolution_work ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.resolution_work_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: scrobbles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.scrobbles (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    played_at timestamp(6) without time zone NOT NULL,
    payload jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    recording_id bigint,
    recording_surface_id bigint,
    source_fingerprint character varying,
    import_page_id bigint,
    lastfm_account_id bigint NOT NULL
);


--
-- Name: scrobbles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.scrobbles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: scrobbles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.scrobbles_id_seq OWNED BY public.scrobbles.id;


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    grant_token text,
    verified_at timestamp(6) without time zone,
    last_seen_at timestamp(6) without time zone,
    shell_username character varying,
    shell_username_issued_at bigint
);


--
-- Name: sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sessions_id_seq OWNED BY public.sessions.id;


--
-- Name: source_deliveries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.source_deliveries (
    id bigint NOT NULL,
    source_fetch_id bigint NOT NULL,
    lastfm_account_id bigint NOT NULL,
    scrobble_id bigint,
    "position" integer NOT NULL,
    classification character varying NOT NULL,
    source_checksum character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT valid_source_delivery CHECK ((("position" > 0) AND ((classification)::text = ANY ((ARRAY['inserted'::character varying, 'repeat'::character varying, 'metadata_changed'::character varying, 'legacy_first'::character varying, 'now_playing'::character varying, 'undated'::character varying, 'malformed'::character varying, 'outside_window'::character varying])::text[]))))
);


--
-- Name: source_deliveries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.source_deliveries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: source_deliveries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.source_deliveries_id_seq OWNED BY public.source_deliveries.id;


--
-- Name: source_fetches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.source_fetches (
    id bigint NOT NULL,
    import_run_id bigint NOT NULL,
    lastfm_account_id bigint NOT NULL,
    legacy_import_page_id bigint,
    page_number integer NOT NULL,
    lower_bound bigint,
    upper_bound bigint NOT NULL,
    phase character varying DEFAULT 'main'::character varying NOT NULL,
    request_parameters jsonb DEFAULT '{}'::jsonb NOT NULL,
    requested_at timestamp(6) without time zone NOT NULL,
    outcome character varying NOT NULL,
    raw_body bytea,
    checksum character varying,
    error_class character varying,
    retry_number integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT valid_source_fetch CHECK (((page_number > 0) AND ((phase)::text = ANY ((ARRAY['main'::character varying, 'boundary'::character varying])::text[])) AND ((raw_body IS NULL) OR (checksum IS NOT NULL)))),
    CONSTRAINT verified_source_fetch_checksum CHECK (((raw_body IS NULL) OR ((checksum)::text = encode(sha256(raw_body), 'hex'::text))))
);


--
-- Name: source_fetches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.source_fetches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: source_fetches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.source_fetches_id_seq OWNED BY public.source_fetches.id;


--
-- Name: user_lastfm_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_lastfm_accounts (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    lastfm_account_id bigint NOT NULL,
    import_allowed boolean DEFAULT true NOT NULL,
    interpretation_allowed boolean DEFAULT true NOT NULL,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: user_lastfm_accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_lastfm_accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_lastfm_accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_lastfm_accounts_id_seq OWNED BY public.user_lastfm_accounts.id;


--
-- Name: user_timezones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_timezones (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    timezone character varying NOT NULL,
    effective_from timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: user_timezones_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_timezones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_timezones_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_timezones_id_seq OWNED BY public.user_timezones.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    lastfm_username character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    email_address character varying,
    password_digest character varying,
    activated_at timestamp(6) without time zone,
    disabled_at timestamp(6) without time zone,
    oidc_issuer character varying,
    oidc_subject character varying
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: artists id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.artists ALTER COLUMN id SET DEFAULT nextval('public.artists_id_seq'::regclass);


--
-- Name: catalog_imports id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_imports ALTER COLUMN id SET DEFAULT nextval('public.catalog_imports_id_seq'::regclass);


--
-- Name: catalog_revisions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_revisions ALTER COLUMN id SET DEFAULT nextval('public.catalog_revisions_id_seq'::regclass);


--
-- Name: catalog_track_slots id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_track_slots ALTER COLUMN id SET DEFAULT nextval('public.catalog_track_slots_id_seq'::regclass);


--
-- Name: daily_listens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_listens ALTER COLUMN id SET DEFAULT nextval('public.daily_listens_id_seq'::regclass);


--
-- Name: import_pages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_pages ALTER COLUMN id SET DEFAULT nextval('public.import_pages_id_seq'::regclass);


--
-- Name: import_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_runs ALTER COLUMN id SET DEFAULT nextval('public.import_runs_id_seq'::regclass);


--
-- Name: ingestion_budgets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingestion_budgets ALTER COLUMN id SET DEFAULT nextval('public.ingestion_budgets_id_seq'::regclass);


--
-- Name: ingestion_issues id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingestion_issues ALTER COLUMN id SET DEFAULT nextval('public.ingestion_issues_id_seq'::regclass);


--
-- Name: lastfm_account_names id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lastfm_account_names ALTER COLUMN id SET DEFAULT nextval('public.lastfm_account_names_id_seq'::regclass);


--
-- Name: lastfm_accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lastfm_accounts ALTER COLUMN id SET DEFAULT nextval('public.lastfm_accounts_id_seq'::regclass);


--
-- Name: listening_profile_publication_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.listening_profile_publication_events ALTER COLUMN id SET DEFAULT nextval('public.listening_profile_publication_events_id_seq'::regclass);


--
-- Name: listening_profiles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.listening_profiles ALTER COLUMN id SET DEFAULT nextval('public.listening_profiles_id_seq'::regclass);


--
-- Name: musical_identity_decisions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.musical_identity_decisions ALTER COLUMN id SET DEFAULT nextval('public.musical_identity_decisions_id_seq'::regclass);


--
-- Name: oidc_attempts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oidc_attempts ALTER COLUMN id SET DEFAULT nextval('public.oidc_attempts_id_seq'::regclass);


--
-- Name: page_commits id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.page_commits ALTER COLUMN id SET DEFAULT nextval('public.page_commits_id_seq'::regclass);


--
-- Name: recording_artists id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recording_artists ALTER COLUMN id SET DEFAULT nextval('public.recording_artists_id_seq'::regclass);


--
-- Name: recording_source_decisions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recording_source_decisions ALTER COLUMN id SET DEFAULT nextval('public.recording_source_decisions_id_seq'::regclass);


--
-- Name: recording_surfaces id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recording_surfaces ALTER COLUMN id SET DEFAULT nextval('public.recording_surfaces_id_seq'::regclass);


--
-- Name: recordings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recordings ALTER COLUMN id SET DEFAULT nextval('public.recordings_id_seq'::regclass);


--
-- Name: release_artists id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_artists ALTER COLUMN id SET DEFAULT nextval('public.release_artists_id_seq'::regclass);


--
-- Name: release_ranking_decisions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_ranking_decisions ALTER COLUMN id SET DEFAULT nextval('public.release_ranking_decisions_id_seq'::regclass);


--
-- Name: release_recordings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_recordings ALTER COLUMN id SET DEFAULT nextval('public.release_recordings_id_seq'::regclass);


--
-- Name: release_track_listening_decisions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_track_listening_decisions ALTER COLUMN id SET DEFAULT nextval('public.release_track_listening_decisions_id_seq'::regclass);


--
-- Name: releases id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.releases ALTER COLUMN id SET DEFAULT nextval('public.releases_id_seq'::regclass);


--
-- Name: scrobbles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scrobbles ALTER COLUMN id SET DEFAULT nextval('public.scrobbles_id_seq'::regclass);


--
-- Name: sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions ALTER COLUMN id SET DEFAULT nextval('public.sessions_id_seq'::regclass);


--
-- Name: source_deliveries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_deliveries ALTER COLUMN id SET DEFAULT nextval('public.source_deliveries_id_seq'::regclass);


--
-- Name: source_fetches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_fetches ALTER COLUMN id SET DEFAULT nextval('public.source_fetches_id_seq'::regclass);


--
-- Name: user_lastfm_accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_lastfm_accounts ALTER COLUMN id SET DEFAULT nextval('public.user_lastfm_accounts_id_seq'::regclass);


--
-- Name: user_timezones id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_timezones ALTER COLUMN id SET DEFAULT nextval('public.user_timezones_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: artists artists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.artists
    ADD CONSTRAINT artists_pkey PRIMARY KEY (id);


--
-- Name: catalog_imports catalog_imports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_imports
    ADD CONSTRAINT catalog_imports_pkey PRIMARY KEY (id);


--
-- Name: catalog_revisions catalog_revisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_revisions
    ADD CONSTRAINT catalog_revisions_pkey PRIMARY KEY (id);


--
-- Name: catalog_track_slots catalog_track_slots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_track_slots
    ADD CONSTRAINT catalog_track_slots_pkey PRIMARY KEY (id);


--
-- Name: daily_listens daily_listens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_listens
    ADD CONSTRAINT daily_listens_pkey PRIMARY KEY (id);


--
-- Name: import_pages import_pages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_pages
    ADD CONSTRAINT import_pages_pkey PRIMARY KEY (id);


--
-- Name: import_runs import_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_runs
    ADD CONSTRAINT import_runs_pkey PRIMARY KEY (id);


--
-- Name: ingestion_budgets ingestion_budgets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingestion_budgets
    ADD CONSTRAINT ingestion_budgets_pkey PRIMARY KEY (id);


--
-- Name: ingestion_issues ingestion_issues_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingestion_issues
    ADD CONSTRAINT ingestion_issues_pkey PRIMARY KEY (id);


--
-- Name: lastfm_account_names lastfm_account_names_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lastfm_account_names
    ADD CONSTRAINT lastfm_account_names_pkey PRIMARY KEY (id);


--
-- Name: lastfm_accounts lastfm_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lastfm_accounts
    ADD CONSTRAINT lastfm_accounts_pkey PRIMARY KEY (id);


--
-- Name: listening_profile_publication_events listening_profile_publication_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.listening_profile_publication_events
    ADD CONSTRAINT listening_profile_publication_events_pkey PRIMARY KEY (id);


--
-- Name: listening_profiles listening_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.listening_profiles
    ADD CONSTRAINT listening_profiles_pkey PRIMARY KEY (id);


--
-- Name: musical_identity_decisions musical_identity_decisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.musical_identity_decisions
    ADD CONSTRAINT musical_identity_decisions_pkey PRIMARY KEY (id);


--
-- Name: oidc_attempts oidc_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oidc_attempts
    ADD CONSTRAINT oidc_attempts_pkey PRIMARY KEY (id);


--
-- Name: page_commits page_commits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.page_commits
    ADD CONSTRAINT page_commits_pkey PRIMARY KEY (id);


--
-- Name: recording_artists recording_artists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recording_artists
    ADD CONSTRAINT recording_artists_pkey PRIMARY KEY (id);


--
-- Name: recording_source_decisions recording_source_decisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recording_source_decisions
    ADD CONSTRAINT recording_source_decisions_pkey PRIMARY KEY (id);


--
-- Name: recording_surfaces recording_surfaces_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recording_surfaces
    ADD CONSTRAINT recording_surfaces_pkey PRIMARY KEY (id);


--
-- Name: recordings recordings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recordings
    ADD CONSTRAINT recordings_pkey PRIMARY KEY (id);


--
-- Name: release_artists release_artists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_artists
    ADD CONSTRAINT release_artists_pkey PRIMARY KEY (id);


--
-- Name: release_ranking_decisions release_ranking_decisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_ranking_decisions
    ADD CONSTRAINT release_ranking_decisions_pkey PRIMARY KEY (id);


--
-- Name: release_recordings release_recordings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_recordings
    ADD CONSTRAINT release_recordings_pkey PRIMARY KEY (id);


--
-- Name: release_track_listening_decisions release_track_listening_decisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_track_listening_decisions
    ADD CONSTRAINT release_track_listening_decisions_pkey PRIMARY KEY (id);


--
-- Name: releases releases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.releases
    ADD CONSTRAINT releases_pkey PRIMARY KEY (id);


--
-- Name: resolution_assessments resolution_assessments_group_id_version_digest_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_assessments
    ADD CONSTRAINT resolution_assessments_group_id_version_digest_key UNIQUE (group_id, version, digest);


--
-- Name: resolution_assessments resolution_assessments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_assessments
    ADD CONSTRAINT resolution_assessments_pkey PRIMARY KEY (id);


--
-- Name: resolution_decisions resolution_decisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_decisions
    ADD CONSTRAINT resolution_decisions_pkey PRIMARY KEY (id);


--
-- Name: resolution_groups resolution_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_groups
    ADD CONSTRAINT resolution_groups_pkey PRIMARY KEY (id);


--
-- Name: resolution_groups resolution_groups_surface_id_version_claims_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_groups
    ADD CONSTRAINT resolution_groups_surface_id_version_claims_key UNIQUE (surface_id, version, claims);


--
-- Name: resolution_memberships resolution_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_memberships
    ADD CONSTRAINT resolution_memberships_pkey PRIMARY KEY (scrobble_id);


--
-- Name: resolution_pilots resolution_pilots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_pilots
    ADD CONSTRAINT resolution_pilots_pkey PRIMARY KEY (id);


--
-- Name: resolution_provider_budgets resolution_provider_budgets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_provider_budgets
    ADD CONSTRAINT resolution_provider_budgets_pkey PRIMARY KEY (provider);


--
-- Name: resolution_request_cache resolution_request_cache_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_request_cache
    ADD CONSTRAINT resolution_request_cache_pkey PRIMARY KEY (request_key);


--
-- Name: resolution_surfaces resolution_surfaces_lastfm_account_id_exact_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_surfaces
    ADD CONSTRAINT resolution_surfaces_lastfm_account_id_exact_key_key UNIQUE (lastfm_account_id, exact_key);


--
-- Name: resolution_surfaces resolution_surfaces_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_surfaces
    ADD CONSTRAINT resolution_surfaces_pkey PRIMARY KEY (id);


--
-- Name: resolution_work resolution_work_pilot_id_group_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_work
    ADD CONSTRAINT resolution_work_pilot_id_group_id_key UNIQUE (pilot_id, group_id);


--
-- Name: resolution_work resolution_work_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_work
    ADD CONSTRAINT resolution_work_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: scrobbles scrobbles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scrobbles
    ADD CONSTRAINT scrobbles_pkey PRIMARY KEY (id);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: source_deliveries source_deliveries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_deliveries
    ADD CONSTRAINT source_deliveries_pkey PRIMARY KEY (id);


--
-- Name: source_fetches source_fetches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_fetches
    ADD CONSTRAINT source_fetches_pkey PRIMARY KEY (id);


--
-- Name: user_lastfm_accounts user_lastfm_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_lastfm_accounts
    ADD CONSTRAINT user_lastfm_accounts_pkey PRIMARY KEY (id);


--
-- Name: user_timezones user_timezones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_timezones
    ADD CONSTRAINT user_timezones_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: due_lastfm_accounts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX due_lastfm_accounts ON public.lastfm_accounts USING btree (next_poll_at, id) WHERE (sync_enabled AND ((state)::text = 'active'::text));


--
-- Name: idx_catalog_track_slots_edition_position; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_catalog_track_slots_edition_position ON public.catalog_track_slots USING btree (release_id, edition_mbid, medium, "position") WHERE (edition_mbid IS NOT NULL);

--
-- Name: idx_catalog_track_slots_base_position; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_catalog_track_slots_base_position ON public.catalog_track_slots USING btree (release_id, medium, "position") WHERE (edition_mbid IS NULL);


--
-- Name: idx_on_entity_type_entity_id_id_c7b7191f51; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_entity_type_entity_id_id_c7b7191f51 ON public.musical_identity_decisions USING btree (entity_type, entity_id, id);


--
-- Name: idx_on_listening_profile_id_24b6f2d861; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_listening_profile_id_24b6f2d861 ON public.listening_profile_publication_events USING btree (listening_profile_id);


--
-- Name: idx_on_user_id_release_id_id_8bad624ede; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_user_id_release_id_id_8bad624ede ON public.release_ranking_decisions USING btree (user_id, release_id, id);


--
-- Name: index_artists_on_mbid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_artists_on_mbid ON public.artists USING btree (mbid);


--
-- Name: index_artists_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_artists_on_name ON public.artists USING btree (name);


--
-- Name: index_catalog_imports_active_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_catalog_imports_active_entity ON public.catalog_imports USING btree (kind, entity_id) WHERE ((state)::text = ANY ((ARRAY['pending'::character varying, 'refreshing'::character varying])::text[]));


--
-- Name: index_catalog_imports_on_kind_and_entity_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_catalog_imports_on_kind_and_entity_id_and_id ON public.catalog_imports USING btree (kind, entity_id, id);


--
-- Name: index_catalog_imports_on_state_and_due_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_catalog_imports_on_state_and_due_at ON public.catalog_imports USING btree (state, due_at);


--
-- Name: index_catalog_revisions_on_catalog_import_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_catalog_revisions_on_catalog_import_id ON public.catalog_revisions USING btree (catalog_import_id);


--
-- Name: index_catalog_revisions_on_entity_type_and_entity_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_catalog_revisions_on_entity_type_and_entity_id_and_id ON public.catalog_revisions USING btree (entity_type, entity_id, id);


--
-- Name: index_catalog_track_slots_on_recording_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_catalog_track_slots_on_recording_id ON public.catalog_track_slots USING btree (recording_id);


--
-- Name: index_catalog_track_slots_on_release_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_catalog_track_slots_on_release_id ON public.catalog_track_slots USING btree (release_id);


--
-- Name: index_daily_listens_on_recording_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_daily_listens_on_recording_id ON public.daily_listens USING btree (recording_id);


--
-- Name: index_daily_listens_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_daily_listens_on_user_id ON public.daily_listens USING btree (user_id);


--
-- Name: index_daily_listens_on_user_id_and_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_daily_listens_on_user_id_and_date ON public.daily_listens USING btree (user_id, date);


--
-- Name: index_daily_listens_on_user_id_and_recording_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_daily_listens_on_user_id_and_recording_id ON public.daily_listens USING btree (user_id, recording_id);


--
-- Name: index_daily_listens_on_user_id_and_recording_id_and_date; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_daily_listens_on_user_id_and_recording_id_and_date ON public.daily_listens USING btree (user_id, recording_id, date);


--
-- Name: index_daily_listens_on_year; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_daily_listens_on_year ON public.daily_listens USING btree (year);


--
-- Name: index_import_pages_on_import_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_pages_on_import_run_id ON public.import_pages USING btree (import_run_id);


--
-- Name: index_import_pages_on_import_run_id_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_import_pages_on_import_run_id_and_number ON public.import_pages USING btree (import_run_id, number);


--
-- Name: index_import_runs_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_runs_on_created_at ON public.import_runs USING btree (created_at);


--
-- Name: index_import_runs_on_lastfm_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_runs_on_lastfm_account_id ON public.import_runs USING btree (lastfm_account_id);


--
-- Name: index_import_runs_on_range_end_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_runs_on_range_end_at ON public.import_runs USING btree (range_end_at);


--
-- Name: index_import_runs_on_user_and_range; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_runs_on_user_and_range ON public.import_runs USING btree (user_id, range_start_at, range_end_at);


--
-- Name: index_import_runs_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_runs_on_user_id ON public.import_runs USING btree (user_id);


--
-- Name: index_ingestion_budgets_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ingestion_budgets_on_name ON public.ingestion_budgets USING btree (name);


--
-- Name: index_ingestion_issues_on_import_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ingestion_issues_on_import_run_id ON public.ingestion_issues USING btree (import_run_id);


--
-- Name: index_ingestion_issues_on_lastfm_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ingestion_issues_on_lastfm_account_id ON public.ingestion_issues USING btree (lastfm_account_id);


--
-- Name: index_ingestion_issues_on_source_fetch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ingestion_issues_on_source_fetch_id ON public.ingestion_issues USING btree (source_fetch_id);


--
-- Name: index_lastfm_account_names_on_lastfm_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lastfm_account_names_on_lastfm_account_id ON public.lastfm_account_names USING btree (lastfm_account_id);


--
-- Name: index_lastfm_account_names_on_lookup_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_lastfm_account_names_on_lookup_key ON public.lastfm_account_names USING btree (lookup_key);


--
-- Name: index_lastfm_accounts_on_archive_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lastfm_accounts_on_archive_user_id ON public.lastfm_accounts USING btree (archive_user_id);


--
-- Name: index_lastfm_accounts_on_identity_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_lastfm_accounts_on_identity_key ON public.lastfm_accounts USING btree (identity_key);


--
-- Name: index_lastfm_accounts_on_lookup_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_lastfm_accounts_on_lookup_key ON public.lastfm_accounts USING btree (lookup_key);


--
-- Name: index_listening_profiles_on_lastfm_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_listening_profiles_on_lastfm_account_id ON public.listening_profiles USING btree (lastfm_account_id);


--
-- Name: index_listening_profiles_on_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_listening_profiles_on_owner_id ON public.listening_profiles USING btree (owner_id);


--
-- Name: index_musical_identity_decisions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_musical_identity_decisions_on_user_id ON public.musical_identity_decisions USING btree (user_id);


--
-- Name: index_oidc_attempts_on_state; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oidc_attempts_on_state ON public.oidc_attempts USING btree (state);


--
-- Name: index_page_commits_on_import_page_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_page_commits_on_import_page_id ON public.page_commits USING btree (import_page_id);


--
-- Name: index_page_commits_on_source_fetch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_page_commits_on_source_fetch_id ON public.page_commits USING btree (source_fetch_id);


--
-- Name: index_recording_artists_on_artist_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recording_artists_on_artist_id ON public.recording_artists USING btree (artist_id);


--
-- Name: index_recording_artists_on_recording_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recording_artists_on_recording_id ON public.recording_artists USING btree (recording_id);


--
-- Name: index_recording_artists_on_recording_id_and_artist_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_recording_artists_on_recording_id_and_artist_id ON public.recording_artists USING btree (recording_id, artist_id);


--
-- Name: index_recording_source_decisions_on_recording_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recording_source_decisions_on_recording_id ON public.recording_source_decisions USING btree (recording_id);


--
-- Name: index_recording_source_decisions_on_source_mbid_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recording_source_decisions_on_source_mbid_and_id ON public.recording_source_decisions USING btree (source_mbid, id);


--
-- Name: index_recording_surfaces_on_artist_mbid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recording_surfaces_on_artist_mbid ON public.recording_surfaces USING btree (artist_mbid);


--
-- Name: index_recording_surfaces_on_normalized_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_recording_surfaces_on_normalized_key ON public.recording_surfaces USING btree (normalized_key);


--
-- Name: index_recording_surfaces_on_recording_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recording_surfaces_on_recording_id ON public.recording_surfaces USING btree (recording_id);


--
-- Name: index_recording_surfaces_on_track_mbid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recording_surfaces_on_track_mbid ON public.recording_surfaces USING btree (track_mbid);


--
-- Name: index_recordings_on_mbid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_recordings_on_mbid ON public.recordings USING btree (mbid);


--
-- Name: index_recordings_on_title; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recordings_on_title ON public.recordings USING btree (title);


--
-- Name: index_release_artists_on_artist_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_release_artists_on_artist_id ON public.release_artists USING btree (artist_id);


--
-- Name: index_release_artists_on_release_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_release_artists_on_release_id ON public.release_artists USING btree (release_id);


--
-- Name: index_release_artists_on_release_id_and_artist_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_release_artists_on_release_id_and_artist_id ON public.release_artists USING btree (release_id, artist_id);


--
-- Name: index_release_recordings_on_recording_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_release_recordings_on_recording_id ON public.release_recordings USING btree (recording_id);


--
-- Name: index_release_recordings_on_release_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_release_recordings_on_release_id ON public.release_recordings USING btree (release_id);


--
-- Name: index_release_recordings_on_release_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_release_recordings_on_release_id_and_position ON public.release_recordings USING btree (release_id, "position");


--
-- Name: index_release_recordings_on_release_id_and_recording_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_release_recordings_on_release_id_and_recording_id ON public.release_recordings USING btree (release_id, recording_id);


--
-- Name: index_release_track_listening_on_listener_release_recording; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_release_track_listening_on_listener_release_recording ON public.release_track_listening_decisions USING btree (user_id, release_id, recording_id, id);


--
-- Name: index_releases_on_ingested_from_release_mbid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_releases_on_ingested_from_release_mbid ON public.releases USING btree (ingested_from_release_mbid);


--
-- Name: index_releases_on_release_group_mbid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_releases_on_release_group_mbid ON public.releases USING btree (release_group_mbid);


--
-- Name: index_resolution_decisions_on_recording_and_listener; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_resolution_decisions_on_recording_and_listener ON public.resolution_decisions USING btree (recording_id, user_id) WHERE (recording_id IS NOT NULL);


--
-- Name: index_scrobbles_archive_keyset; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scrobbles_archive_keyset ON public.scrobbles USING btree (lastfm_account_id, id);


--
-- Name: index_scrobbles_on_archive_and_exact_surface; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scrobbles_on_archive_and_exact_surface ON public.scrobbles USING btree (lastfm_account_id, public.resolution_surface_key((payload ->> 'artist_name'::text), (payload ->> 'album_name'::text), (payload ->> 'track_name'::text)));


--
-- Name: index_scrobbles_on_import_page_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scrobbles_on_import_page_id ON public.scrobbles USING btree (import_page_id);


--
-- Name: index_scrobbles_on_lastfm_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scrobbles_on_lastfm_account_id ON public.scrobbles USING btree (lastfm_account_id);


--
-- Name: index_scrobbles_on_lastfm_account_id_and_played_at_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scrobbles_on_lastfm_account_id_and_played_at_and_id ON public.scrobbles USING btree (lastfm_account_id, played_at, id);


--
-- Name: index_scrobbles_on_lastfm_account_id_and_source_fingerprint; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_scrobbles_on_lastfm_account_id_and_source_fingerprint ON public.scrobbles USING btree (lastfm_account_id, source_fingerprint);


--
-- Name: index_scrobbles_on_played_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scrobbles_on_played_at ON public.scrobbles USING btree (played_at);


--
-- Name: index_scrobbles_on_recording_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scrobbles_on_recording_id ON public.scrobbles USING btree (recording_id);


--
-- Name: index_scrobbles_on_recording_surface_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scrobbles_on_recording_surface_id ON public.scrobbles USING btree (recording_surface_id);


--
-- Name: index_scrobbles_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scrobbles_on_user_id ON public.scrobbles USING btree (user_id);


--
-- Name: index_scrobbles_on_user_id_and_played_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scrobbles_on_user_id_and_played_at ON public.scrobbles USING btree (user_id, played_at);


--
-- Name: index_scrobbles_on_user_id_and_source_fingerprint; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_scrobbles_on_user_id_and_source_fingerprint ON public.scrobbles USING btree (user_id, source_fingerprint);


--
-- Name: index_sessions_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_expires_at ON public.sessions USING btree (expires_at);


--
-- Name: index_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_user_id ON public.sessions USING btree (user_id);


--
-- Name: index_source_deliveries_on_lastfm_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_source_deliveries_on_lastfm_account_id ON public.source_deliveries USING btree (lastfm_account_id);


--
-- Name: index_source_deliveries_on_scrobble_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_source_deliveries_on_scrobble_id ON public.source_deliveries USING btree (scrobble_id);


--
-- Name: index_source_deliveries_on_source_fetch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_source_deliveries_on_source_fetch_id ON public.source_deliveries USING btree (source_fetch_id);


--
-- Name: index_source_deliveries_on_source_fetch_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_source_deliveries_on_source_fetch_id_and_position ON public.source_deliveries USING btree (source_fetch_id, "position");


--
-- Name: index_source_fetches_on_import_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_source_fetches_on_import_run_id ON public.source_fetches USING btree (import_run_id);


--
-- Name: index_source_fetches_on_lastfm_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_source_fetches_on_lastfm_account_id ON public.source_fetches USING btree (lastfm_account_id);


--
-- Name: index_source_fetches_on_legacy_import_page_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_source_fetches_on_legacy_import_page_id ON public.source_fetches USING btree (legacy_import_page_id);


--
-- Name: index_user_lastfm_accounts_on_lastfm_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_lastfm_accounts_on_lastfm_account_id ON public.user_lastfm_accounts USING btree (lastfm_account_id);


--
-- Name: index_user_lastfm_accounts_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_lastfm_accounts_on_user_id ON public.user_lastfm_accounts USING btree (user_id);


--
-- Name: index_user_lastfm_accounts_on_user_id_and_lastfm_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_user_lastfm_accounts_on_user_id_and_lastfm_account_id ON public.user_lastfm_accounts USING btree (user_id, lastfm_account_id);


--
-- Name: index_user_timezones_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_timezones_on_user_id ON public.user_timezones USING btree (user_id);


--
-- Name: index_users_on_normalized_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_normalized_email ON public.users USING btree (lower((email_address)::text));


--
-- Name: index_users_on_oidc_issuer_and_oidc_subject; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_oidc_issuer_and_oidc_subject ON public.users USING btree (oidc_issuer, oidc_subject);


--
-- Name: one_active_import_per_account; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_active_import_per_account ON public.import_runs USING btree (lastfm_account_id) WHERE (status = ANY (ARRAY[0, 1]));


--
-- Name: resolution_decision_predecessor; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX resolution_decision_predecessor ON public.resolution_decisions USING btree (surface_id, COALESCE(user_id, (0)::bigint), COALESCE(scrobble_id, (0)::bigint), COALESCE(predecessor_id, (0)::bigint));


--
-- Name: resolution_decisions_surface_id_user_id_scrobble_id_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX resolution_decisions_surface_id_user_id_scrobble_id_id_idx ON public.resolution_decisions USING btree (surface_id, user_id, scrobble_id, id DESC);


--
-- Name: resolution_memberships_surface_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX resolution_memberships_surface_id_idx ON public.resolution_memberships USING btree (surface_id);


--
-- Name: resolution_request_cache_expires_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX resolution_request_cache_expires_at_idx ON public.resolution_request_cache USING btree (expires_at);


--
-- Name: resolution_work_pilot_id_state_due_at_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX resolution_work_pilot_id_state_due_at_id_idx ON public.resolution_work USING btree (pilot_id, state, due_at, id);


--
-- Name: catalog_revisions catalog_revisions_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER catalog_revisions_immutable BEFORE DELETE OR UPDATE ON public.catalog_revisions FOR EACH ROW EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: catalog_revisions catalog_revisions_no_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER catalog_revisions_no_truncate BEFORE TRUNCATE ON public.catalog_revisions FOR EACH STATEMENT EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: resolution_decisions check_resolution_decision; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER check_resolution_decision BEFORE INSERT ON public.resolution_decisions FOR EACH ROW EXECUTE FUNCTION public.resolution_check_decision();


--
-- Name: resolution_memberships check_resolution_membership; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER check_resolution_membership BEFORE INSERT ON public.resolution_memberships FOR EACH ROW EXECUTE FUNCTION public.resolution_check_membership();


--
-- Name: resolution_work check_resolution_work; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER check_resolution_work BEFORE INSERT OR UPDATE ON public.resolution_work FOR EACH ROW EXECUTE FUNCTION public.resolution_check_work();


--
-- Name: resolution_pilots keep_resolution_pilot_bounds; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER keep_resolution_pilot_bounds BEFORE UPDATE ON public.resolution_pilots FOR EACH ROW EXECUTE FUNCTION public.resolution_keep_pilot_bounds();


--
-- Name: import_pages preserve_raw_page; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER preserve_raw_page BEFORE DELETE OR UPDATE ON public.import_pages FOR EACH ROW EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: import_runs preserve_run_origin; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER preserve_run_origin BEFORE UPDATE ON public.import_runs FOR EACH ROW EXECUTE FUNCTION public.muzeum_preserve_ingestion_identity();


--
-- Name: scrobbles preserve_scrobble_identifier; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER preserve_scrobble_identifier BEFORE UPDATE ON public.scrobbles FOR EACH ROW EXECUTE FUNCTION public.muzeum_preserve_scrobble_identifier();


--
-- Name: scrobbles preserve_scrobble_source; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER preserve_scrobble_source BEFORE DELETE OR UPDATE ON public.scrobbles FOR EACH ROW EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: lastfm_accounts preserve_source_account_identity; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER preserve_source_account_identity BEFORE UPDATE ON public.lastfm_accounts FOR EACH ROW EXECUTE FUNCTION public.muzeum_preserve_ingestion_identity();


--
-- Name: ingestion_issues retain_ingestion_issues; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_ingestion_issues BEFORE DELETE OR UPDATE ON public.ingestion_issues FOR EACH ROW EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: lastfm_account_names retain_lastfm_account_names; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_lastfm_account_names BEFORE DELETE OR UPDATE ON public.lastfm_account_names FOR EACH ROW EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: listening_profile_publication_events retain_listening_profile_publication_events; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_listening_profile_publication_events BEFORE DELETE OR UPDATE ON public.listening_profile_publication_events FOR EACH ROW EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: page_commits retain_page_commits; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_page_commits BEFORE DELETE OR UPDATE ON public.page_commits FOR EACH ROW EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: resolution_assessments retain_resolution_assessments; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_resolution_assessments BEFORE DELETE OR UPDATE ON public.resolution_assessments FOR EACH ROW EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: resolution_decisions retain_resolution_decisions; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_resolution_decisions BEFORE DELETE OR UPDATE ON public.resolution_decisions FOR EACH ROW EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: resolution_groups retain_resolution_groups; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_resolution_groups BEFORE DELETE OR UPDATE ON public.resolution_groups FOR EACH ROW EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: resolution_memberships retain_resolution_memberships; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_resolution_memberships BEFORE DELETE OR UPDATE ON public.resolution_memberships FOR EACH ROW EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: resolution_surfaces retain_resolution_surfaces; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_resolution_surfaces BEFORE DELETE OR UPDATE ON public.resolution_surfaces FOR EACH ROW EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: source_deliveries retain_source_deliveries; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_source_deliveries BEFORE DELETE OR UPDATE ON public.source_deliveries FOR EACH ROW EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: source_fetches retain_source_fetches; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_source_fetches BEFORE DELETE OR UPDATE ON public.source_fetches FOR EACH ROW EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: import_pages retain_truncate_import_pages; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_truncate_import_pages BEFORE TRUNCATE ON public.import_pages FOR EACH STATEMENT EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: ingestion_issues retain_truncate_ingestion_issues; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_truncate_ingestion_issues BEFORE TRUNCATE ON public.ingestion_issues FOR EACH STATEMENT EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: lastfm_account_names retain_truncate_lastfm_account_names; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_truncate_lastfm_account_names BEFORE TRUNCATE ON public.lastfm_account_names FOR EACH STATEMENT EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: page_commits retain_truncate_page_commits; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_truncate_page_commits BEFORE TRUNCATE ON public.page_commits FOR EACH STATEMENT EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: resolution_assessments retain_truncate_resolution_assessments; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_truncate_resolution_assessments BEFORE TRUNCATE ON public.resolution_assessments FOR EACH STATEMENT EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: resolution_decisions retain_truncate_resolution_decisions; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_truncate_resolution_decisions BEFORE TRUNCATE ON public.resolution_decisions FOR EACH STATEMENT EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: resolution_groups retain_truncate_resolution_groups; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_truncate_resolution_groups BEFORE TRUNCATE ON public.resolution_groups FOR EACH STATEMENT EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: resolution_memberships retain_truncate_resolution_memberships; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_truncate_resolution_memberships BEFORE TRUNCATE ON public.resolution_memberships FOR EACH STATEMENT EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: resolution_surfaces retain_truncate_resolution_surfaces; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_truncate_resolution_surfaces BEFORE TRUNCATE ON public.resolution_surfaces FOR EACH STATEMENT EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: scrobbles retain_truncate_scrobbles; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_truncate_scrobbles BEFORE TRUNCATE ON public.scrobbles FOR EACH STATEMENT EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: source_deliveries retain_truncate_source_deliveries; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_truncate_source_deliveries BEFORE TRUNCATE ON public.source_deliveries FOR EACH STATEMENT EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: source_fetches retain_truncate_source_fetches; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_truncate_source_fetches BEFORE TRUNCATE ON public.source_fetches FOR EACH STATEMENT EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: source_deliveries validate_delivery_account; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER validate_delivery_account BEFORE INSERT ON public.source_deliveries FOR EACH ROW EXECUTE FUNCTION public.muzeum_check_delivery_account();


--
-- Name: page_commits validate_page_commit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER validate_page_commit BEFORE INSERT ON public.page_commits FOR EACH ROW EXECUTE FUNCTION public.muzeum_validate_page_commit();


--
-- Name: user_lastfm_accounts withdraw_profile_on_grant_loss; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER withdraw_profile_on_grant_loss AFTER DELETE OR UPDATE OF revoked_at, user_id, lastfm_account_id ON public.user_lastfm_accounts FOR EACH ROW EXECUTE FUNCTION public.withdraw_profile_on_grant_loss();


--
-- Name: recording_surfaces fk_rails_00389e2abb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recording_surfaces
    ADD CONSTRAINT fk_rails_00389e2abb FOREIGN KEY (recording_id) REFERENCES public.recordings(id);


--
-- Name: daily_listens fk_rails_09d5917322; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_listens
    ADD CONSTRAINT fk_rails_09d5917322 FOREIGN KEY (recording_id) REFERENCES public.recordings(id);


--
-- Name: page_commits fk_rails_0f75bd4a1e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.page_commits
    ADD CONSTRAINT fk_rails_0f75bd4a1e FOREIGN KEY (source_fetch_id) REFERENCES public.source_fetches(id);


--
-- Name: release_ranking_decisions fk_rails_1218ae2788; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_ranking_decisions
    ADD CONSTRAINT fk_rails_1218ae2788 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: recording_artists fk_rails_1465a00657; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recording_artists
    ADD CONSTRAINT fk_rails_1465a00657 FOREIGN KEY (recording_id) REFERENCES public.recordings(id);


--
-- Name: lastfm_accounts fk_rails_23b29f2a8f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lastfm_accounts
    ADD CONSTRAINT fk_rails_23b29f2a8f FOREIGN KEY (archive_user_id) REFERENCES public.users(id);


--
-- Name: daily_listens fk_rails_2901fe8f5e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_listens
    ADD CONSTRAINT fk_rails_2901fe8f5e FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: release_track_listening_decisions fk_rails_34a42965e1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_track_listening_decisions
    ADD CONSTRAINT fk_rails_34a42965e1 FOREIGN KEY (recording_id) REFERENCES public.recordings(id);


--
-- Name: scrobbles fk_rails_34b49bed2b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scrobbles
    ADD CONSTRAINT fk_rails_34b49bed2b FOREIGN KEY (recording_surface_id) REFERENCES public.recording_surfaces(id);


--
-- Name: source_deliveries fk_rails_35b08045ae; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_deliveries
    ADD CONSTRAINT fk_rails_35b08045ae FOREIGN KEY (scrobble_id) REFERENCES public.scrobbles(id);


--
-- Name: release_track_listening_decisions fk_rails_3be875762b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_track_listening_decisions
    ADD CONSTRAINT fk_rails_3be875762b FOREIGN KEY (release_id) REFERENCES public.releases(id);


--
-- Name: catalog_track_slots fk_rails_428a52fbd2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_track_slots
    ADD CONSTRAINT fk_rails_428a52fbd2 FOREIGN KEY (recording_id) REFERENCES public.recordings(id);


--
-- Name: source_fetches fk_rails_4718593825; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_fetches
    ADD CONSTRAINT fk_rails_4718593825 FOREIGN KEY (lastfm_account_id) REFERENCES public.lastfm_accounts(id);


--
-- Name: listening_profiles fk_rails_4d632b423f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.listening_profiles
    ADD CONSTRAINT fk_rails_4d632b423f FOREIGN KEY (owner_id) REFERENCES public.users(id);


--
-- Name: scrobbles fk_rails_4e5508c5bb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scrobbles
    ADD CONSTRAINT fk_rails_4e5508c5bb FOREIGN KEY (import_page_id) REFERENCES public.import_pages(id);


--
-- Name: recording_artists fk_rails_58c044bcb1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recording_artists
    ADD CONSTRAINT fk_rails_58c044bcb1 FOREIGN KEY (artist_id) REFERENCES public.artists(id);


--
-- Name: catalog_track_slots fk_rails_657ee70ea3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_track_slots
    ADD CONSTRAINT fk_rails_657ee70ea3 FOREIGN KEY (release_id) REFERENCES public.releases(id);


--
-- Name: release_artists fk_rails_662dad9174; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_artists
    ADD CONSTRAINT fk_rails_662dad9174 FOREIGN KEY (artist_id) REFERENCES public.artists(id);


--
-- Name: release_artists fk_rails_693dddc660; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_artists
    ADD CONSTRAINT fk_rails_693dddc660 FOREIGN KEY (release_id) REFERENCES public.releases(id);


--
-- Name: ingestion_issues fk_rails_6a8902e64d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingestion_issues
    ADD CONSTRAINT fk_rails_6a8902e64d FOREIGN KEY (import_run_id) REFERENCES public.import_runs(id);


--
-- Name: user_lastfm_accounts fk_rails_6e29dbccab; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_lastfm_accounts
    ADD CONSTRAINT fk_rails_6e29dbccab FOREIGN KEY (lastfm_account_id) REFERENCES public.lastfm_accounts(id);


--
-- Name: release_recordings fk_rails_715caed593; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_recordings
    ADD CONSTRAINT fk_rails_715caed593 FOREIGN KEY (release_id) REFERENCES public.releases(id);


--
-- Name: scrobbles fk_rails_7184308464; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scrobbles
    ADD CONSTRAINT fk_rails_7184308464 FOREIGN KEY (recording_id) REFERENCES public.recordings(id);


--
-- Name: release_track_listening_decisions fk_rails_718c4192d7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_track_listening_decisions
    ADD CONSTRAINT fk_rails_718c4192d7 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: import_runs fk_rails_726701e472; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_runs
    ADD CONSTRAINT fk_rails_726701e472 FOREIGN KEY (lastfm_account_id) REFERENCES public.lastfm_accounts(id);


--
-- Name: sessions fk_rails_758836b4f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_758836b4f0 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: user_lastfm_accounts fk_rails_79eb00a28c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_lastfm_accounts
    ADD CONSTRAINT fk_rails_79eb00a28c FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: import_runs fk_rails_8125fa0177; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_runs
    ADD CONSTRAINT fk_rails_8125fa0177 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: listening_profile_publication_events fk_rails_841d09a8a9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.listening_profile_publication_events
    ADD CONSTRAINT fk_rails_841d09a8a9 FOREIGN KEY (listening_profile_id) REFERENCES public.listening_profiles(id);


--
-- Name: import_pages fk_rails_86b2e76ad1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_pages
    ADD CONSTRAINT fk_rails_86b2e76ad1 FOREIGN KEY (import_run_id) REFERENCES public.import_runs(id);


--
-- Name: musical_identity_decisions fk_rails_89e2521d19; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.musical_identity_decisions
    ADD CONSTRAINT fk_rails_89e2521d19 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: source_deliveries fk_rails_91dfac599f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_deliveries
    ADD CONSTRAINT fk_rails_91dfac599f FOREIGN KEY (lastfm_account_id) REFERENCES public.lastfm_accounts(id);


--
-- Name: page_commits fk_rails_94899db3fe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.page_commits
    ADD CONSTRAINT fk_rails_94899db3fe FOREIGN KEY (import_page_id) REFERENCES public.import_pages(id);


--
-- Name: lastfm_account_names fk_rails_9daefd50e1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lastfm_account_names
    ADD CONSTRAINT fk_rails_9daefd50e1 FOREIGN KEY (lastfm_account_id) REFERENCES public.lastfm_accounts(id);


--
-- Name: source_fetches fk_rails_aa664485cd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_fetches
    ADD CONSTRAINT fk_rails_aa664485cd FOREIGN KEY (legacy_import_page_id) REFERENCES public.import_pages(id);


--
-- Name: source_fetches fk_rails_ac630f7ffa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_fetches
    ADD CONSTRAINT fk_rails_ac630f7ffa FOREIGN KEY (import_run_id) REFERENCES public.import_runs(id);


--
-- Name: ingestion_issues fk_rails_ad49facee4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingestion_issues
    ADD CONSTRAINT fk_rails_ad49facee4 FOREIGN KEY (lastfm_account_id) REFERENCES public.lastfm_accounts(id);


--
-- Name: scrobbles fk_rails_b3495516b0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scrobbles
    ADD CONSTRAINT fk_rails_b3495516b0 FOREIGN KEY (lastfm_account_id) REFERENCES public.lastfm_accounts(id);


--
-- Name: release_ranking_decisions fk_rails_bb0b040719; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_ranking_decisions
    ADD CONSTRAINT fk_rails_bb0b040719 FOREIGN KEY (release_id) REFERENCES public.releases(id);


--
-- Name: listening_profiles fk_rails_bca1665695; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.listening_profiles
    ADD CONSTRAINT fk_rails_bca1665695 FOREIGN KEY (lastfm_account_id) REFERENCES public.lastfm_accounts(id);


--
-- Name: source_deliveries fk_rails_dbc221d7c5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_deliveries
    ADD CONSTRAINT fk_rails_dbc221d7c5 FOREIGN KEY (source_fetch_id) REFERENCES public.source_fetches(id);


--
-- Name: ingestion_issues fk_rails_dcb1c83871; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingestion_issues
    ADD CONSTRAINT fk_rails_dcb1c83871 FOREIGN KEY (source_fetch_id) REFERENCES public.source_fetches(id);


--
-- Name: recording_source_decisions fk_rails_f0a2b062ed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recording_source_decisions
    ADD CONSTRAINT fk_rails_f0a2b062ed FOREIGN KEY (recording_id) REFERENCES public.recordings(id);


--
-- Name: release_recordings fk_rails_f336446026; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_recordings
    ADD CONSTRAINT fk_rails_f336446026 FOREIGN KEY (recording_id) REFERENCES public.recordings(id);


--
-- Name: catalog_revisions fk_rails_ffc437f4fb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_revisions
    ADD CONSTRAINT fk_rails_ffc437f4fb FOREIGN KEY (catalog_import_id) REFERENCES public.catalog_imports(id);


--
-- Name: resolution_assessments resolution_assessments_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_assessments
    ADD CONSTRAINT resolution_assessments_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.resolution_groups(id);


--
-- Name: resolution_assessments resolution_assessments_suggested_recording_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_assessments
    ADD CONSTRAINT resolution_assessments_suggested_recording_id_fkey FOREIGN KEY (suggested_recording_id) REFERENCES public.recordings(id);


--
-- Name: resolution_decisions resolution_decisions_assessment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_decisions
    ADD CONSTRAINT resolution_decisions_assessment_id_fkey FOREIGN KEY (assessment_id) REFERENCES public.resolution_assessments(id);


--
-- Name: resolution_decisions resolution_decisions_predecessor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_decisions
    ADD CONSTRAINT resolution_decisions_predecessor_id_fkey FOREIGN KEY (predecessor_id) REFERENCES public.resolution_decisions(id);


--
-- Name: resolution_decisions resolution_decisions_recording_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_decisions
    ADD CONSTRAINT resolution_decisions_recording_id_fkey FOREIGN KEY (recording_id) REFERENCES public.recordings(id);


--
-- Name: resolution_decisions resolution_decisions_scrobble_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_decisions
    ADD CONSTRAINT resolution_decisions_scrobble_id_fkey FOREIGN KEY (scrobble_id) REFERENCES public.resolution_memberships(scrobble_id);


--
-- Name: resolution_decisions resolution_decisions_surface_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_decisions
    ADD CONSTRAINT resolution_decisions_surface_id_fkey FOREIGN KEY (surface_id) REFERENCES public.resolution_surfaces(id);


--
-- Name: resolution_decisions resolution_decisions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_decisions
    ADD CONSTRAINT resolution_decisions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: resolution_groups resolution_groups_surface_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_groups
    ADD CONSTRAINT resolution_groups_surface_id_fkey FOREIGN KEY (surface_id) REFERENCES public.resolution_surfaces(id);


--
-- Name: resolution_memberships resolution_memberships_scrobble_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_memberships
    ADD CONSTRAINT resolution_memberships_scrobble_id_fkey FOREIGN KEY (scrobble_id) REFERENCES public.scrobbles(id);


--
-- Name: resolution_memberships resolution_memberships_surface_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_memberships
    ADD CONSTRAINT resolution_memberships_surface_id_fkey FOREIGN KEY (surface_id) REFERENCES public.resolution_surfaces(id);


--
-- Name: resolution_pilots resolution_pilots_lastfm_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_pilots
    ADD CONSTRAINT resolution_pilots_lastfm_account_id_fkey FOREIGN KEY (lastfm_account_id) REFERENCES public.lastfm_accounts(id);


--
-- Name: resolution_surfaces resolution_surfaces_lastfm_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_surfaces
    ADD CONSTRAINT resolution_surfaces_lastfm_account_id_fkey FOREIGN KEY (lastfm_account_id) REFERENCES public.lastfm_accounts(id);


--
-- Name: resolution_work resolution_work_assessment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_work
    ADD CONSTRAINT resolution_work_assessment_id_fkey FOREIGN KEY (assessment_id) REFERENCES public.resolution_assessments(id);


--
-- Name: resolution_work resolution_work_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_work
    ADD CONSTRAINT resolution_work_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.resolution_groups(id);


--
-- Name: resolution_work resolution_work_pilot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_work
    ADD CONSTRAINT resolution_work_pilot_id_fkey FOREIGN KEY (pilot_id) REFERENCES public.resolution_pilots(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261124162000'),
('20261124030000'),
('20261123231500'),
('20261123230000'),
('20261122223000'),
('20261122170100'),
('20261122170000'),
('20261121160000'),
('20261119150200'),
('20261119150100'),
('20261119150000'),
('20261118120200'),
('20261118120100'),
('20261118120000'),
('20261117150200'),
('20261117150100'),
('20261117150000'),
('20261116121000'),
('20261116120000'),
('20261116010000'),
('20260128223604'),
('20260123172731'),
('20260123044632'),
('20260123043345'),
('20260122224844'),
('20260122195903'),
('20260121151132'),
('20260117205410'),
('20260117202859'),
('20260116164231'),
('20260114024325'),
('20260113162103'),
('20260113152343'),
('20260113142421'),
('20260112213929');

