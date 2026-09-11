-- ============================================================
-- 009 — Variantes (produto × cor × tamanho), preço em centavos,
--       fotos com ordem e vínculo de cor, configurações da loja.
--
-- Esta migration NÃO remove nada: `products.price`, `products.color`
-- e `products.sizes` continuam existindo e passam a ser mantidos em
-- sincronia a partir das variantes (ver trigger no final).
-- ============================================================

-- ------------------------------------------------------------
-- Configurações da loja (linha única)
-- ------------------------------------------------------------
create table if not exists store_settings (
  id                  int primary key default 1 check (id = 1),
  -- Colchão anti-oversell: quantas peças NUNCA são oferecidas no site,
  -- ficando reservadas para a venda no balcão.
  site_safety_stock   int not null default 1 check (site_safety_stock >= 0),
  -- Desconto acima deste percentual exige senha da dona no PDV.
  pos_discount_limit  numeric(5,2) not null default 15,
  -- Minutos até a reserva de um pedido não confirmado expirar.
  reservation_minutes int not null default 2880,
  store_name          text not null default 'MineClothes',
  whatsapp_number     text not null default '5511900000000',  -- número fictício no case
  updated_at          timestamptz not null default now()
);

insert into store_settings (id) values (1) on conflict (id) do nothing;

alter table store_settings enable row level security;

drop policy if exists "store_settings_service_only" on store_settings;
create policy "store_settings_service_only"
  on store_settings for all
  using (auth.role() = 'service_role');

-- ------------------------------------------------------------
-- Colunas novas em products
-- ------------------------------------------------------------
alter table products add column if not exists price_cents         int;
alter table products add column if not exists compare_price_cents int;
alter table products add column if not exists slug                text;
alter table products add column if not exists status              text not null default 'ativo';
alter table products add column if not exists size_grid           text not null default 'letra';
alter table products add column if not exists updated_at          timestamptz not null default now();
alter table products add column if not exists archived_at         timestamptz;

do $do$ begin
  alter table products add constraint products_status_check
    check (status in ('rascunho', 'ativo', 'arquivado'));
exception when duplicate_object then null; end $do$;

do $do$ begin
  alter table products add constraint products_size_grid_check
    check (size_grid in ('letra', 'numerica', 'unico', 'infantil'));
exception when duplicate_object then null; end $do$;

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------

-- Remove acentos sem depender da extensão `unaccent`.
create or replace function unaccent_fallback(raw text)
returns text
language sql
immutable
as $fn$
  select translate(
    coalesce(raw, ''),
    'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ',
    'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN'
  );
$fn$;

-- "Camisa Básica" -> "camisa-basica"
create or replace function slugify(raw text)
returns text
language sql
immutable
as $fn$
  select trim(both '-' from regexp_replace(
    lower(unaccent_fallback(raw)),
    '[^a-z0-9]+', '-', 'g'
  ));
$fn$;

-- "R$ 89,90" -> 8990 ; "1.299,00" -> 129900 ; "89.90" -> 8990
create or replace function parse_price_cents(raw text)
returns int
language plpgsql
immutable
as $fn$
declare
  cleaned text;
begin
  if raw is null then return null; end if;

  cleaned := regexp_replace(raw, '[^0-9,.]', '', 'g');
  if cleaned = '' then return null; end if;

  -- Formato brasileiro: ponto separa milhar, vírgula separa decimal.
  if position(',' in cleaned) > 0 then
    cleaned := replace(cleaned, '.', '');
    cleaned := replace(cleaned, ',', '.');
  end if;

  return round(cleaned::numeric * 100)::int;
exception when others then
  return null;
end $fn$;

-- ------------------------------------------------------------
-- Variantes: a unidade real de estoque
-- ------------------------------------------------------------
create table if not exists product_variants (
  id                  uuid primary key default gen_random_uuid(),
  product_id          uuid not null references products(id) on delete cascade,
  color               text not null default '',
  size                text not null,
  sku                 text unique,
  barcode             text,
  stock_on_hand       int  not null default 0 check (stock_on_hand >= 0),
  stock_reserved      int  not null default 0 check (stock_reserved >= 0),
  low_stock_threshold int  not null default 2,
  -- null = herda o preço do produto
  price_cents         int,
  cost_cents          int  not null default 0,
  active              boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (product_id, color, size)
);

create index if not exists product_variants_product_idx on product_variants(product_id);
create index if not exists product_variants_barcode_idx on product_variants(barcode);
create index if not exists product_variants_active_idx  on product_variants(active);

-- ------------------------------------------------------------
-- Fotos: com ordem e vínculo opcional de cor
-- ------------------------------------------------------------
create table if not exists product_images (
  id          uuid primary key default gen_random_uuid(),
  product_id  uuid not null references products(id) on delete cascade,
  url         text not null,
  sort_order  int  not null default 0,
  color       text not null default '',
  created_at  timestamptz not null default now()
);

create index if not exists product_images_product_idx on product_images(product_id, sort_order);

-- ------------------------------------------------------------
-- Disponibilidade — o site NUNCA lê stock_on_hand direto.
--
-- ATENÇÃO: esta view expõe `cost_cents` e por isso NÃO pode ser legível
-- pelos papéis públicos. O app sempre a consulta com a service role.
-- Para leitura pública existe `product_variants_public`, mais abaixo, que
-- não traz custo nem saldo bruto.
-- ------------------------------------------------------------
create or replace view product_variants_available as
select
  v.*,
  greatest(v.stock_on_hand - v.stock_reserved - s.site_safety_stock, 0) as available_site,
  greatest(v.stock_on_hand - v.stock_reserved, 0)                       as available_loja,
  coalesce(v.price_cents, p.price_cents)                                as effective_price_cents,
  p.status                                                              as product_status,
  p.name                                                                as product_name,
  p.slug                                                                as product_slug
from product_variants v
join products p on p.id = v.product_id
cross join store_settings s
where s.id = 1;

-- ------------------------------------------------------------
-- Leitura pública sem dado sensível.
--
-- Só o que a vitrine precisa: o que dá para comprar e por quanto.
-- Custo, saldo real e reservas ficam de fora.
-- ------------------------------------------------------------
create or replace view product_variants_public as
select
  v.id,
  v.product_id,
  v.color,
  v.size,
  greatest(v.stock_on_hand - v.stock_reserved - s.site_safety_stock, 0) as available_site,
  coalesce(v.price_cents, p.price_cents) as price_cents
from product_variants v
join products p on p.id = v.product_id
cross join store_settings s
where s.id = 1
  and v.active
  and p.status = 'ativo';

-- ------------------------------------------------------------
-- RLS
-- ------------------------------------------------------------
alter table product_variants enable row level security;
alter table product_images   enable row level security;

-- Sem leitura pública na tabela: ela carrega cost_cents.
drop policy if exists "product_variants_public_read"  on product_variants;
drop policy if exists "product_variants_service_write" on product_variants;
create policy "product_variants_service_only"
  on product_variants for all using (auth.role() = 'service_role');

-- Views no Postgres rodam com os direitos do dono e ignoram a RLS da tabela
-- base, então não basta tirar a política: o acesso precisa ser revogado.
-- No Supabase, `anon` e `authenticated` ganham SELECT por padrão.
revoke all on product_variants            from anon, authenticated;
revoke all on product_variants_available  from anon, authenticated;
grant select on product_variants_public   to anon, authenticated;

drop policy if exists "product_images_public_read"  on product_images;
drop policy if exists "product_images_service_write" on product_images;
create policy "product_images_public_read"
  on product_images for select using (true);
create policy "product_images_service_write"
  on product_images for all using (auth.role() = 'service_role');

-- ------------------------------------------------------------
-- Sincronia reversa: products.sizes é mantido a partir das variantes
-- enquanto o site público ainda o lê. A coluna sai na etapa 10.
-- ------------------------------------------------------------
create or replace function sync_product_sizes()
returns trigger
language plpgsql
as $fn$
declare
  pid uuid := coalesce(new.product_id, old.product_id);
begin
  update products p
     set sizes = coalesce((
           select jsonb_agg(jsonb_build_object('size', t.size, 'stock', t.stock)
                            order by t.ord, t.size)
             from (
               select v.size,
                      sum(v.stock_on_hand)::int as stock,
                      min(coalesce(array_position(
                        array['PP','P','M','G','GG','XGG'], v.size), 99)) as ord
                 from product_variants v
                where v.product_id = pid and v.active
             group by v.size
             ) t
         ), '[]'::jsonb),
         updated_at = now()
   where p.id = pid;
  return null;
end $fn$;

drop trigger if exists product_variants_sync_sizes on product_variants;
create trigger product_variants_sync_sizes
  after insert or update or delete on product_variants
  for each row execute function sync_product_sizes();
