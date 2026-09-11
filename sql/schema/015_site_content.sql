-- Conteúdo editável do site.
--
-- Uma linha por seção da vitrine (`key`), com os campos daquela seção em
-- `value`. O formato é jsonb porque cada seção tem campos diferentes e eles
-- mudam junto com o layout — uma coluna por texto viraria uma migration a
-- cada ajuste de copy, que é exatamente o problema que esta tabela resolve.
--
-- Linha ausente = o site usa o padrão de fábrica de `src/data/content.ts`.
-- Por isso não há seed aqui: no dia do deploy a vitrine continua idêntica.

create table if not exists site_content (
  key         text primary key,
  value       jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now(),
  updated_by  text
);

alter table site_content enable row level security;

-- Mesma dupla de policies dos banners: a vitrine lê, só o service role escreve.
drop policy if exists "site_content_public_read" on site_content;
drop policy if exists "site_content_service_write" on site_content;

create policy "site_content_public_read" on site_content for select using (true);
create policy "site_content_service_write" on site_content for all using (auth.role() = 'service_role');
