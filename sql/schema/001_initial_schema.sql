-- ============================================================
-- MINE - Schema inicial do banco de dados
-- ============================================================

-- Extensão para UUIDs
create extension if not exists "pgcrypto";

-- ============================================================
-- CATÁLOGO
-- ============================================================

create table if not exists products (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  model       text not null default '',
  color       text not null default '',
  category    text not null,
  price       text not null,
  description text not null default '',
  images      text[] not null default '{}',
  sizes       jsonb not null default '[]',
  in_promotion boolean not null default false,
  created_at  timestamptz not null default now()
);

create index if not exists products_category_idx on products(category);
create index if not exists products_in_promotion_idx on products(in_promotion);

-- ============================================================
-- FUNIL WHATSAPP
-- ============================================================

create table if not exists contacts (
  id                uuid primary key default gen_random_uuid(),
  whatsapp_number   text not null unique,
  name              text,
  status            text not null default 'new' check (status in ('new', 'active', 'customer', 'inactive')),
  tags              text[] not null default '{}',
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  last_interaction  timestamptz
);

create index if not exists contacts_whatsapp_idx on contacts(whatsapp_number);
create index if not exists contacts_status_idx on contacts(status);

create table if not exists messages (
  id              uuid primary key default gen_random_uuid(),
  contact_id      uuid not null references contacts(id) on delete cascade,
  content         text not null,
  direction       text not null check (direction in ('inbound', 'outbound')),
  message_type    text not null default 'text' check (message_type in ('text', 'image', 'template')),
  delivery_status text not null default 'sent' check (delivery_status in ('sent', 'delivered', 'read', 'failed')),
  metadata        jsonb default '{}',
  created_at      timestamptz not null default now()
);

create index if not exists messages_contact_idx on messages(contact_id);
create index if not exists messages_created_at_idx on messages(created_at desc);

create table if not exists orders (
  id          uuid primary key default gen_random_uuid(),
  contact_id  uuid not null references contacts(id) on delete restrict,
  status      text not null default 'pending' check (status in ('pending', 'confirmed', 'delivered', 'cancelled')),
  notes       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists orders_contact_idx on orders(contact_id);
create index if not exists orders_status_idx on orders(status);

create table if not exists order_items (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references orders(id) on delete cascade,
  product_id  uuid not null references products(id) on delete restrict,
  size        text not null,
  quantity    int not null default 1 check (quantity > 0),
  unit_price  numeric(10,2) not null,
  created_at  timestamptz not null default now()
);

create index if not exists order_items_order_idx on order_items(order_id);

-- ============================================================
-- CAMPANHAS
-- ============================================================

create table if not exists campaigns (
  id               uuid primary key default gen_random_uuid(),
  type             text not null check (type in ('weekly', 'stock_clearance', 'birthday', 'custom')),
  message_template text not null,
  scheduled_at     timestamptz,
  sent_at          timestamptz,
  status           text not null default 'scheduled' check (status in ('scheduled', 'sent', 'failed')),
  created_at       timestamptz not null default now()
);

create table if not exists campaign_contacts (
  id              uuid primary key default gen_random_uuid(),
  campaign_id     uuid not null references campaigns(id) on delete cascade,
  contact_id      uuid not null references contacts(id) on delete cascade,
  sent_at         timestamptz,
  delivery_status text default 'pending',
  unique(campaign_id, contact_id)
);

create index if not exists campaign_contacts_campaign_idx on campaign_contacts(campaign_id);

-- ============================================================
-- ANALYTICS
-- ============================================================

create table if not exists analytics_daily (
  id                      uuid primary key default gen_random_uuid(),
  date                    date not null unique,
  site_visitors           int not null default 0,
  meta_ads_clicks         int not null default 0,
  meta_ads_impressions    int not null default 0,
  whatsapp_conversations  int not null default 0,
  orders_confirmed        int not null default 0,
  cpm                     numeric(10,4),
  ctr                     numeric(10,4),
  cpc                     numeric(10,4),
  roas                    numeric(10,4)
);

-- ============================================================
-- RLS (Row Level Security)
-- ============================================================

-- Habilitar RLS em todas as tabelas
alter table products         enable row level security;
alter table contacts         enable row level security;
alter table messages         enable row level security;
alter table orders           enable row level security;
alter table order_items      enable row level security;
alter table campaigns        enable row level security;
alter table campaign_contacts enable row level security;
alter table analytics_daily  enable row level security;

-- products: leitura pública (catálogo do site), escrita apenas via service role
create policy "products_public_read"
  on products for select
  using (true);

create policy "products_service_write"
  on products for all
  using (auth.role() = 'service_role');

-- Demais tabelas: apenas service role (acesso via n8n/API backend)
create policy "contacts_service_only"
  on contacts for all
  using (auth.role() = 'service_role');

create policy "messages_service_only"
  on messages for all
  using (auth.role() = 'service_role');

create policy "orders_service_only"
  on orders for all
  using (auth.role() = 'service_role');

create policy "order_items_service_only"
  on order_items for all
  using (auth.role() = 'service_role');

create policy "campaigns_service_only"
  on campaigns for all
  using (auth.role() = 'service_role');

create policy "campaign_contacts_service_only"
  on campaign_contacts for all
  using (auth.role() = 'service_role');

create policy "analytics_service_only"
  on analytics_daily for all
  using (auth.role() = 'service_role');

-- ============================================================
-- STORAGE BUCKET para imagens de produtos
-- ============================================================

insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do nothing;

create policy "product_images_public_read"
  on storage.objects for select
  using (bucket_id = 'product-images');

create policy "product_images_service_write"
  on storage.objects for insert
  with check (bucket_id = 'product-images' and auth.role() = 'service_role');

create policy "product_images_service_delete"
  on storage.objects for delete
  using (bucket_id = 'product-images' and auth.role() = 'service_role');
