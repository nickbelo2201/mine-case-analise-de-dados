-- ============================================================
-- Shim para rodar as migrations fora do Supabase.
--
-- As migrations de produção usam objetos que o Supabase cria por
-- conta própria: os papéis `anon` / `authenticated` / `service_role`,
-- a função `auth.role()` (lida pelas políticas de RLS) e o schema
-- `storage`. Aqui eles são recriados no mínimo necessário para que o
-- schema real rode num Postgres puro, sem alterar uma linha dele.
-- ============================================================

create extension if not exists pgcrypto;

do $$ begin
  create role anon;          exception when duplicate_object then null; end $$;
do $$ begin
  create role authenticated; exception when duplicate_object then null; end $$;
do $$ begin
  create role service_role;  exception when duplicate_object then null; end $$;

create schema if not exists extensions;

create schema if not exists auth;
create or replace function auth.role() returns text
language sql stable
as $$
  select coalesce(current_setting('request.jwt.claim.role', true), 'service_role')
$$;

create schema if not exists storage;
create table if not exists storage.buckets (
  id     text primary key,
  name   text not null,
  public boolean not null default false
);
create table if not exists storage.objects (
  id        uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets(id),
  name      text
);
alter table storage.objects enable row level security;
