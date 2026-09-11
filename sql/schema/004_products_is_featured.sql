-- Tag "Mais escolhida": marca no admin quais peças aparecem na seção
-- "Mais escolhidos" da home. No máximo 6, limite garantido pelo admin.
alter table products add column if not exists is_featured boolean not null default false;

create index if not exists products_is_featured_idx on products(is_featured);
