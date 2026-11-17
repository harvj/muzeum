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
    secondary_type integer DEFAULT 0 NOT NULL
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
    last_seen_at timestamp(6) without time zone
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
-- Name: release_recordings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_recordings ALTER COLUMN id SET DEFAULT nextval('public.release_recordings_id_seq'::regclass);


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
-- Name: release_recordings release_recordings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_recordings
    ADD CONSTRAINT release_recordings_pkey PRIMARY KEY (id);


--
-- Name: releases releases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.releases
    ADD CONSTRAINT releases_pkey PRIMARY KEY (id);


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
-- Name: index_artists_on_mbid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_artists_on_mbid ON public.artists USING btree (mbid);


--
-- Name: index_artists_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_artists_on_name ON public.artists USING btree (name);


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
-- Name: index_releases_on_ingested_from_release_mbid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_releases_on_ingested_from_release_mbid ON public.releases USING btree (ingested_from_release_mbid);


--
-- Name: index_releases_on_release_group_mbid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_releases_on_release_group_mbid ON public.releases USING btree (release_group_mbid);


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
-- Name: page_commits retain_page_commits; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER retain_page_commits BEFORE DELETE OR UPDATE ON public.page_commits FOR EACH ROW EXECUTE FUNCTION public.muzeum_preserve_source();


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
-- Name: source_fetches fk_rails_4718593825; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_fetches
    ADD CONSTRAINT fk_rails_4718593825 FOREIGN KEY (lastfm_account_id) REFERENCES public.lastfm_accounts(id);


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
-- Name: import_pages fk_rails_86b2e76ad1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_pages
    ADD CONSTRAINT fk_rails_86b2e76ad1 FOREIGN KEY (import_run_id) REFERENCES public.import_runs(id);


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
-- Name: release_recordings fk_rails_f336446026; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_recordings
    ADD CONSTRAINT fk_rails_f336446026 FOREIGN KEY (recording_id) REFERENCES public.recordings(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
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

