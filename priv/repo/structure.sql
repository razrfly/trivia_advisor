--
-- PostgreSQL database dump
--

-- Dumped from database version 15.12 (Postgres.app)
-- Dumped by pg_dump version 15.12 (Postgres.app)

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
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- Name: event_frequency; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.event_frequency AS ENUM (
    'weekly',
    'biweekly',
    'monthly',
    'irregular'
);


--
-- Name: oban_job_state; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.oban_job_state AS ENUM (
    'available',
    'scheduled',
    'executing',
    'retryable',
    'completed',
    'discarded',
    'cancelled'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: cities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cities (
    id bigint NOT NULL,
    country_id bigint NOT NULL,
    name character varying(255) NOT NULL,
    slug character varying(255) NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    latitude numeric(10,6),
    longitude numeric(10,6)
);


--
-- Name: cities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cities_id_seq OWNED BY public.cities.id;


--
-- Name: countries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.countries (
    id bigint NOT NULL,
    code character varying(2) NOT NULL,
    name character varying(255) NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    slug character varying(255) NOT NULL
);


--
-- Name: countries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.countries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: countries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.countries_id_seq OWNED BY public.countries.id;


--
-- Name: event_sources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_sources (
    id bigint NOT NULL,
    event_id bigint NOT NULL,
    source_url character varying(255) NOT NULL,
    last_seen_at timestamp(0) without time zone,
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    metadata jsonb,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    source_id bigint NOT NULL
);


--
-- Name: event_sources_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.event_sources_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: event_sources_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.event_sources_id_seq OWNED BY public.event_sources.id;


--
-- Name: events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.events (
    id bigint NOT NULL,
    venue_id bigint NOT NULL,
    name character varying(255) NOT NULL,
    day_of_week integer NOT NULL,
    start_time time(0) without time zone NOT NULL,
    frequency public.event_frequency DEFAULT 'weekly'::public.event_frequency NOT NULL,
    entry_fee_cents integer DEFAULT 0,
    description text,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    hero_image character varying(255),
    performer_id bigint
);


--
-- Name: events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.events_id_seq OWNED BY public.events.id;


--
-- Name: oban_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oban_jobs (
    id bigint NOT NULL,
    state public.oban_job_state DEFAULT 'available'::public.oban_job_state NOT NULL,
    queue text DEFAULT 'default'::text NOT NULL,
    worker text NOT NULL,
    args jsonb DEFAULT '{}'::jsonb NOT NULL,
    errors jsonb[] DEFAULT ARRAY[]::jsonb[] NOT NULL,
    attempt integer DEFAULT 0 NOT NULL,
    max_attempts integer DEFAULT 20 NOT NULL,
    inserted_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    scheduled_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    attempted_at timestamp without time zone,
    completed_at timestamp without time zone,
    attempted_by text[],
    discarded_at timestamp without time zone,
    priority integer DEFAULT 0 NOT NULL,
    tags text[] DEFAULT ARRAY[]::text[],
    meta jsonb DEFAULT '{}'::jsonb,
    cancelled_at timestamp without time zone,
    CONSTRAINT attempt_range CHECK (((attempt >= 0) AND (attempt <= max_attempts))),
    CONSTRAINT positive_max_attempts CHECK ((max_attempts > 0)),
    CONSTRAINT queue_length CHECK (((char_length(queue) > 0) AND (char_length(queue) < 128))),
    CONSTRAINT worker_length CHECK (((char_length(worker) > 0) AND (char_length(worker) < 128)))
);


--
-- Name: TABLE oban_jobs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.oban_jobs IS '12';


--
-- Name: oban_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oban_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oban_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oban_jobs_id_seq OWNED BY public.oban_jobs.id;


--
-- Name: oban_peers; Type: TABLE; Schema: public; Owner: -
--

CREATE UNLOGGED TABLE public.oban_peers (
    name text NOT NULL,
    node text NOT NULL,
    started_at timestamp without time zone NOT NULL,
    expires_at timestamp without time zone NOT NULL
);


--
-- Name: performers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.performers (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    source_id bigint NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    profile_image jsonb
);


--
-- Name: performers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.performers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: performers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.performers_id_seq OWNED BY public.performers.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


--
-- Name: scrape_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.scrape_logs (
    id bigint NOT NULL,
    source_id bigint NOT NULL,
    event_count integer DEFAULT 0,
    success boolean DEFAULT false NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb,
    error jsonb DEFAULT '{}'::jsonb,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: scrape_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.scrape_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: scrape_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.scrape_logs_id_seq OWNED BY public.scrape_logs.id;


--
-- Name: sources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sources (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    website_url character varying(255) NOT NULL,
    slug character varying(255) NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: sources_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sources_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sources_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sources_id_seq OWNED BY public.sources.id;


--
-- Name: venues; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.venues (
    id bigint NOT NULL,
    city_id bigint NOT NULL,
    name character varying(255) NOT NULL,
    address character varying(255),
    postcode character varying(255),
    latitude numeric(10,6) NOT NULL,
    longitude numeric(10,6) NOT NULL,
    place_id character varying(255),
    phone character varying(255),
    website character varying(255),
    slug character varying(255) NOT NULL,
    metadata jsonb,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    facebook character varying(255),
    instagram character varying(255),
    google_place_images jsonb DEFAULT '[]'::jsonb
);


--
-- Name: venues_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.venues_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: venues_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.venues_id_seq OWNED BY public.venues.id;


--
-- Name: cities id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities ALTER COLUMN id SET DEFAULT nextval('public.cities_id_seq'::regclass);


--
-- Name: countries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.countries ALTER COLUMN id SET DEFAULT nextval('public.countries_id_seq'::regclass);


--
-- Name: event_sources id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_sources ALTER COLUMN id SET DEFAULT nextval('public.event_sources_id_seq'::regclass);


--
-- Name: events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events ALTER COLUMN id SET DEFAULT nextval('public.events_id_seq'::regclass);


--
-- Name: oban_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_jobs ALTER COLUMN id SET DEFAULT nextval('public.oban_jobs_id_seq'::regclass);


--
-- Name: performers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.performers ALTER COLUMN id SET DEFAULT nextval('public.performers_id_seq'::regclass);


--
-- Name: scrape_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scrape_logs ALTER COLUMN id SET DEFAULT nextval('public.scrape_logs_id_seq'::regclass);


--
-- Name: sources id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources ALTER COLUMN id SET DEFAULT nextval('public.sources_id_seq'::regclass);


--
-- Name: venues id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues ALTER COLUMN id SET DEFAULT nextval('public.venues_id_seq'::regclass);


--
-- Name: cities cities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_pkey PRIMARY KEY (id);


--
-- Name: countries countries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.countries
    ADD CONSTRAINT countries_pkey PRIMARY KEY (id);


--
-- Name: event_sources event_sources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_sources
    ADD CONSTRAINT event_sources_pkey PRIMARY KEY (id);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);


--
-- Name: oban_jobs non_negative_priority; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.oban_jobs
    ADD CONSTRAINT non_negative_priority CHECK ((priority >= 0)) NOT VALID;


--
-- Name: oban_jobs oban_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_jobs
    ADD CONSTRAINT oban_jobs_pkey PRIMARY KEY (id);


--
-- Name: oban_peers oban_peers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_peers
    ADD CONSTRAINT oban_peers_pkey PRIMARY KEY (name);


--
-- Name: performers performers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.performers
    ADD CONSTRAINT performers_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: scrape_logs scrape_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scrape_logs
    ADD CONSTRAINT scrape_logs_pkey PRIMARY KEY (id);


--
-- Name: sources sources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources
    ADD CONSTRAINT sources_pkey PRIMARY KEY (id);


--
-- Name: venues venues_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_pkey PRIMARY KEY (id);


--
-- Name: cities_country_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cities_country_id_index ON public.cities USING btree (country_id);


--
-- Name: cities_latitude_longitude_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cities_latitude_longitude_index ON public.cities USING btree (latitude, longitude);


--
-- Name: cities_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX cities_slug_index ON public.cities USING btree (slug);


--
-- Name: countries_code_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX countries_code_index ON public.countries USING btree (code);


--
-- Name: countries_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX countries_slug_index ON public.countries USING btree (slug);


--
-- Name: event_sources_event_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX event_sources_event_id_index ON public.event_sources USING btree (event_id);


--
-- Name: event_sources_event_id_source_url_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX event_sources_event_id_source_url_index ON public.event_sources USING btree (event_id, source_url);


--
-- Name: event_sources_source_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX event_sources_source_id_index ON public.event_sources USING btree (source_id);


--
-- Name: events_venue_id_day_of_week_start_time_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX events_venue_id_day_of_week_start_time_index ON public.events USING btree (venue_id, day_of_week, start_time);


--
-- Name: events_venue_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX events_venue_id_index ON public.events USING btree (venue_id);


--
-- Name: oban_jobs_args_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_args_index ON public.oban_jobs USING gin (args);


--
-- Name: oban_jobs_meta_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_meta_index ON public.oban_jobs USING gin (meta);


--
-- Name: oban_jobs_state_queue_priority_scheduled_at_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_state_queue_priority_scheduled_at_id_index ON public.oban_jobs USING btree (state, queue, priority, scheduled_at, id);


--
-- Name: performers_source_id_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX performers_source_id_name_index ON public.performers USING btree (source_id, name);


--
-- Name: scrape_logs_source_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX scrape_logs_source_id_index ON public.scrape_logs USING btree (source_id);


--
-- Name: sources_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sources_slug_index ON public.sources USING btree (slug);


--
-- Name: sources_website_url_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sources_website_url_index ON public.sources USING btree (website_url);


--
-- Name: venues_city_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX venues_city_id_index ON public.venues USING btree (city_id);


--
-- Name: venues_metadata_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX venues_metadata_idx ON public.venues USING gin (metadata jsonb_path_ops);


--
-- Name: venues_place_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX venues_place_id_index ON public.venues USING btree (place_id);


--
-- Name: venues_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX venues_slug_index ON public.venues USING btree (slug);


--
-- Name: cities cities_country_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_country_id_fkey FOREIGN KEY (country_id) REFERENCES public.countries(id) ON DELETE CASCADE;


--
-- Name: event_sources event_sources_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_sources
    ADD CONSTRAINT event_sources_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;


--
-- Name: event_sources event_sources_source_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_sources
    ADD CONSTRAINT event_sources_source_id_fkey FOREIGN KEY (source_id) REFERENCES public.sources(id) ON DELETE CASCADE;


--
-- Name: events events_performer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_performer_id_fkey FOREIGN KEY (performer_id) REFERENCES public.performers(id);


--
-- Name: events events_venue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_venue_id_fkey FOREIGN KEY (venue_id) REFERENCES public.venues(id) ON DELETE CASCADE;


--
-- Name: performers performers_source_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.performers
    ADD CONSTRAINT performers_source_id_fkey FOREIGN KEY (source_id) REFERENCES public.sources(id);


--
-- Name: scrape_logs scrape_logs_source_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scrape_logs
    ADD CONSTRAINT scrape_logs_source_id_fkey FOREIGN KEY (source_id) REFERENCES public.sources(id) ON DELETE CASCADE;


--
-- Name: venues venues_city_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_city_id_fkey FOREIGN KEY (city_id) REFERENCES public.cities(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

INSERT INTO public."schema_migrations" (version) VALUES (20250210204717);
INSERT INTO public."schema_migrations" (version) VALUES (20250210205423);
INSERT INTO public."schema_migrations" (version) VALUES (20250210205750);
INSERT INTO public."schema_migrations" (version) VALUES (20250210211257);
INSERT INTO public."schema_migrations" (version) VALUES (20250210212131);
INSERT INTO public."schema_migrations" (version) VALUES (20250210213716);
INSERT INTO public."schema_migrations" (version) VALUES (20250210214042);
INSERT INTO public."schema_migrations" (version) VALUES (20250210214758);
INSERT INTO public."schema_migrations" (version) VALUES (20250210220000);
INSERT INTO public."schema_migrations" (version) VALUES (20250212194500);
INSERT INTO public."schema_migrations" (version) VALUES (20250213000000);
INSERT INTO public."schema_migrations" (version) VALUES (20250213135445);
INSERT INTO public."schema_migrations" (version) VALUES (20250214000000);
INSERT INTO public."schema_migrations" (version) VALUES (20250214000003);
INSERT INTO public."schema_migrations" (version) VALUES (20250214000004);
INSERT INTO public."schema_migrations" (version) VALUES (20250214000005);
INSERT INTO public."schema_migrations" (version) VALUES (20250214000006);
INSERT INTO public."schema_migrations" (version) VALUES (20250221114524);
INSERT INTO public."schema_migrations" (version) VALUES (20250221114525);
INSERT INTO public."schema_migrations" (version) VALUES (20250221114526);
INSERT INTO public."schema_migrations" (version) VALUES (20250226123304);
INSERT INTO public."schema_migrations" (version) VALUES (20250226134235);
INSERT INTO public."schema_migrations" (version) VALUES (20250303204410);
INSERT INTO public."schema_migrations" (version) VALUES (20250303211218);
