-- Produtos podem pertencer a mais de uma categoria.
-- `category` continua sendo a categoria principal (tipo de peça);
-- `extra_categories` guarda slugs adicionais (ex.: luxo, casual, dia-a-dia).
alter table products add column if not exists extra_categories text[] not null default '{}';
create index if not exists products_extra_categories_idx on products using gin (extra_categories);

-- Categorias de curadoria existem e têm página própria, mas ficam fora
-- do menu do topo e da grade de categorias da home.
alter table categories add column if not exists show_in_nav boolean not null default true;

insert into categories (name, slug, parent_id, sort_order, active, show_in_nav)
values
  ('Dia a Dia', 'dia-a-dia', null, 100, true, false),
  ('Casual',    'casual',    null, 101, true, false),
  ('Luxo',      'luxo',      null, 102, true, false)
on conflict (slug) do nothing;
