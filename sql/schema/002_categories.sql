create table if not exists categories (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  slug        text not null unique,
  parent_id   uuid references categories(id) on delete set null,
  image_url   text,
  sort_order  int not null default 0,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

create index if not exists categories_slug_idx   on categories(slug);
create index if not exists categories_parent_idx on categories(parent_id);
create index if not exists categories_sort_idx   on categories(sort_order);

alter table categories enable row level security;

create policy "categories_public_read"
  on categories for select
  using (true);

create policy "categories_service_write"
  on categories for all
  using (auth.role() = 'service_role');

insert into categories (name, slug, sort_order) values
  ('Camisetas', 'camisetas', 1),
  ('Calças',    'calcas',    2),
  ('Bermudas',  'bermudas',  3),
  ('Moletons',  'moletons',  4),
  ('Jaquetas',  'jaquetas',  5)
on conflict (slug) do nothing;
