-- ============================================================
-- Shim para rodar as migrations fora do Supabase.
--
-- As migrations de produção usam objetos que o Supabase cria por
-- conta própria: os papéis `anon` / `authenticated` / `service_role`,
-- a função `auth.role()` (lida pelas políticas de RLS) e o schema
-- `storage`. Aqui eles são recriados no mínimo necessário para que o
-- schema real rode num Postgres puro, sem alterar uma linha dele.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$ BEGIN
  CREATE role anon;          EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE role authenticated; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE role service_role;  EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE SCHEMA IF NOT EXISTS extensions;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE OR REPLACE FUNCTION auth.role() RETURNS TEXT
LANGUAGE SQL STABLE
AS $$
  SELECT COALESCE(current_setting('request.jwt.claim.role', TRUE), 'service_role')
$$;

CREATE SCHEMA IF NOT EXISTS storage;
CREATE TABLE IF NOT EXISTS storage.buckets (
  id     TEXT PRIMARY KEY,
  name   TEXT NOT NULL,
  public BOOLEAN NOT NULL DEFAULT FALSE
);
CREATE TABLE IF NOT EXISTS storage.objects (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id TEXT REFERENCES storage.buckets(id),
  name      TEXT
);
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
