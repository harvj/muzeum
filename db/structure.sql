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
-- Name: muzeum_preserve_source(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.muzeum_preserve_source() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
    country character varying,
    created_at timestamp(6) without time zone NOT NULL,
    mbid character varying,
    name character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
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
    created_at timestamp(6) without time zone NOT NULL,
    date date NOT NULL,
    listen_count integer DEFAULT 0 NOT NULL,
    recording_id bigint NOT NULL,
    total_duration_ms bigint DEFAULT 0 NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint NOT NULL,
    year smallint NOT NULL
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
    artists_created integer,
    created_at timestamp(6) without time zone NOT NULL,
    notes jsonb,
    range_end_at timestamp(6) without time zone,
    range_start_at timestamp(6) without time zone,
    recordings_created integer,
    scrobbles_processed integer,
    status integer DEFAULT 0 NOT NULL,
    unmapped_recordings integer,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint NOT NULL,
    next_page integer DEFAULT 1 NOT NULL,
    upper_bound bigint,
    total_pages integer,
    expected_count bigint,
    last_error character varying,
    last_success_at timestamp(6) without time zone,
    source_username character varying
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
-- Name: recording_artists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recording_artists (
    id bigint NOT NULL,
    artist_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    "position" integer,
    recording_id bigint NOT NULL,
    role integer DEFAULT 0 NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    weight double precision DEFAULT 1.0 NOT NULL
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
    album_mbid character varying,
    album_name character varying,
    artist_mbid character varying,
    artist_name character varying NOT NULL,
    chosen_release_candidate_index integer,
    created_at timestamp(6) without time zone NOT NULL,
    ingest_log jsonb DEFAULT '[]'::jsonb NOT NULL,
    ingested_release_id bigint,
    normalized_key character varying NOT NULL,
    observed_count integer DEFAULT 1 NOT NULL,
    recording_id bigint,
    release_candidates jsonb DEFAULT '[]'::jsonb,
    track_mbid character varying,
    track_name character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
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
    created_at timestamp(6) without time zone NOT NULL,
    duration_ms integer,
    mbid character varying,
    title character varying NOT NULL,
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
    artist_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    "position" integer,
    release_id bigint NOT NULL,
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
    created_at timestamp(6) without time zone NOT NULL,
    "position" integer NOT NULL,
    recording_id bigint NOT NULL,
    release_id bigint NOT NULL,
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
    ingested_from_release_mbid character varying,
    primary_type integer DEFAULT 0 NOT NULL,
    release_day integer,
    release_group_mbid character varying,
    release_month integer,
    release_year integer,
    secondary_type integer DEFAULT 0 NOT NULL,
    source character varying DEFAULT 'musicbrainz'::character varying NOT NULL,
    title character varying NOT NULL
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
    created_at timestamp(6) without time zone NOT NULL,
    payload jsonb NOT NULL,
    played_at timestamp(6) without time zone NOT NULL,
    recording_id bigint,
    recording_surface_id bigint,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint NOT NULL,
    source_fingerprint character varying,
    import_page_id bigint
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
    created_at timestamp(6) without time zone NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint NOT NULL,
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
-- Name: user_timezones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_timezones (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    effective_from timestamp(6) without time zone NOT NULL,
    timezone character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint NOT NULL
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
    activated_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    disabled_at timestamp(6) without time zone,
    email_address character varying,
    lastfm_username character varying,
    password_digest character varying,
    updated_at timestamp(6) without time zone NOT NULL,
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
-- Name: oidc_attempts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oidc_attempts ALTER COLUMN id SET DEFAULT nextval('public.oidc_attempts_id_seq'::regclass);


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
-- Name: oidc_attempts oidc_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oidc_attempts
    ADD CONSTRAINT oidc_attempts_pkey PRIMARY KEY (id);


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
-- Name: index_oidc_attempts_on_state; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oidc_attempts_on_state ON public.oidc_attempts USING btree (state);


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
-- Name: index_user_timezones_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_timezones_on_user_id ON public.user_timezones USING btree (user_id);


--
-- Name: index_users_on_lastfm_username; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_lastfm_username ON public.users USING btree (lastfm_username);


--
-- Name: index_users_on_normalized_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_normalized_email ON public.users USING btree (lower((email_address)::text));


--
-- Name: index_users_on_oidc_issuer_and_oidc_subject; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_oidc_issuer_and_oidc_subject ON public.users USING btree (oidc_issuer, oidc_subject);


--
-- Name: one_active_import_per_user; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_active_import_per_user ON public.import_runs USING btree (user_id) WHERE (status = ANY (ARRAY[0, 1]));


--
-- Name: unique_normalized_lastfm_username; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX unique_normalized_lastfm_username ON public.users USING btree (lower((lastfm_username)::text));


--
-- Name: import_pages preserve_raw_page; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER preserve_raw_page BEFORE DELETE OR UPDATE ON public.import_pages FOR EACH ROW EXECUTE FUNCTION public.muzeum_preserve_source();


--
-- Name: scrobbles preserve_scrobble_source; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER preserve_scrobble_source BEFORE DELETE OR UPDATE ON public.scrobbles FOR EACH ROW EXECUTE FUNCTION public.muzeum_preserve_source();


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
-- Name: recording_artists fk_rails_1465a00657; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recording_artists
    ADD CONSTRAINT fk_rails_1465a00657 FOREIGN KEY (recording_id) REFERENCES public.recordings(id);


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
-- Name: sessions fk_rails_758836b4f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_758836b4f0 FOREIGN KEY (user_id) REFERENCES public.users(id);


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
-- Name: release_recordings fk_rails_f336446026; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_recordings
    ADD CONSTRAINT fk_rails_f336446026 FOREIGN KEY (recording_id) REFERENCES public.recordings(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
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

