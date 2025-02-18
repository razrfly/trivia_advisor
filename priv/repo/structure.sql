--
-- PostgreSQL database dump
--

-- Dumped from database version 15.10 (Postgres.app)
-- Dumped by pg_dump version 15.10 (Postgres.app)

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
    updated_at timestamp(0) without time zone NOT NULL
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
    updated_at timestamp(0) without time zone NOT NULL
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
    updated_at timestamp(0) without time zone NOT NULL
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
    updated_at timestamp(0) without time zone NOT NULL
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
-- Name: cities_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX cities_slug_index ON public.cities USING btree (slug);


--
-- Name: countries_code_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX countries_code_index ON public.countries USING btree (code);


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
-- Name: events events_venue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_venue_id_fkey FOREIGN KEY (venue_id) REFERENCES public.venues(id) ON DELETE CASCADE;


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
