create table if not exists banners (
  id          uuid primary key default gen_random_uuid(),
  slot        text not null unique,
  image_url   text,
  updated_at  timestamptz not null default now()
);

alter table banners enable row level security;

create policy "banners_public_read" on banners for select using (true);
create policy "banners_service_write" on banners for all using (auth.role() = 'service_role');

insert into banners (slot, image_url) values
  ('hero_nova_colecao',     '/images/hero-colecao-nova.png'),
  ('hero_estilo_proprio',   '/images/hero-estilo-proprio.png'),
  ('text_banner_luxo',      '/images/banner-nobre.webp'),
  ('text_banner_casual',    '/images/banner-ecologico.webp'),
  ('text_banner_dia_a_dia', '/images/hero-distincao-desktop.webp')
on conflict (slot) do nothing;
