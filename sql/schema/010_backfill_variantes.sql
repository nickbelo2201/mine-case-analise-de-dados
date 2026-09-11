-- ============================================================
-- 010 — Migração dos dados existentes para o novo modelo.
--
-- Idempotente: pode rodar mais de uma vez sem duplicar nada.
-- Não apaga NENHUM dado antigo — `price`, `color`, `sizes` e `images`
-- continuam intactos como rede de segurança até a etapa 10 do plano.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Preço: texto ("R$ 89,90") -> centavos
-- ------------------------------------------------------------
update products
   set price_cents = parse_price_cents(price)
 where price_cents is null;

-- ------------------------------------------------------------
-- 2. Slug único a partir de modelo + nome + cor
--    (a cor entra porque hoje cada cor é um produto separado;
--     depois da consolidação os slugs seguem válidos)
-- ------------------------------------------------------------
with base as (
  select id,
         nullif(slugify(concat_ws('-', nullif(model, ''), name, nullif(color, ''))), '') as s,
         row_number() over (
           partition by slugify(concat_ws('-', nullif(model, ''), name, nullif(color, '')))
           order by created_at
         ) as n
    from products
   where slug is null
)
update products p
   set slug = case when base.n = 1 then base.s
                   else base.s || '-' || base.n end
  from base
 where p.id = base.id
   and base.s is not null;

-- Qualquer produto sem nome aproveitável cai no id curto.
update products
   set slug = 'produto-' || left(id::text, 8)
 where slug is null;

do $do$ begin
  create unique index products_slug_key on products(slug);
exception when duplicate_table then null; end $do$;

-- ------------------------------------------------------------
-- 3. sizes JSONB -> linhas em product_variants
--    Cor da variante = products.color (o modelo antigo).
--    SKU = MODELO-COR-TAMANHO, com o id curto como desempate.
-- ------------------------------------------------------------
insert into product_variants (product_id, color, size, sku, stock_on_hand, price_cents, cost_cents)
select p.id,
       coalesce(p.color, ''),
       s.size,
       upper(concat_ws('-',
         nullif(slugify(coalesce(nullif(p.model, ''), p.name)), ''),
         nullif(slugify(coalesce(p.color, '')), ''),
         slugify(s.size),
         left(p.id::text, 4)
       )),
       greatest(s.stock, 0),
       null,   -- herda o preço do produto
       0       -- custo desconhecido: a dona preenche ou vem da entrada de compra
  from products p
  cross join lateral (
    select item ->> 'size'                              as size,
           coalesce((item ->> 'stock')::int, 0)         as stock
      from jsonb_array_elements(coalesce(p.sizes, '[]'::jsonb)) as item
     where nullif(item ->> 'size', '') is not null
  ) s
 on conflict (product_id, color, size) do nothing;

-- ------------------------------------------------------------
-- 4. images text[] -> product_images preservando a ordem
--    A primeira imagem continua sendo a capa (sort_order = 0).
-- ------------------------------------------------------------
insert into product_images (product_id, url, sort_order, color)
select p.id, img.url, img.ord - 1, coalesce(p.color, '')
  from products p
  cross join lateral unnest(coalesce(p.images, '{}')) with ordinality as img(url, ord)
 where not exists (
   select 1 from product_images pi
    where pi.product_id = p.id and pi.url = img.url
 );

-- ------------------------------------------------------------
-- 5. Produto sem preço válido não pode ficar "ativo" no site.
--    Vira rascunho e o admin mostra o motivo na tela.
-- ------------------------------------------------------------
update products
   set status = 'rascunho'
 where status = 'ativo'
   and (price_cents is null or price_cents <= 0);

-- ------------------------------------------------------------
-- 6. Relatório de candidatos à consolidação de cores.
--    NÃO funde nada — a fusão é manual, revisada pela dona no admin.
--    Mesma peça (modelo + nome) cadastrada em cores diferentes.
-- ------------------------------------------------------------
create or replace view color_merge_candidates as
select slugify(concat_ws('-', nullif(p.model, ''), p.name)) as merge_key,
       min(p.model)                as model,
       min(p.name)                 as name,
       count(*)                    as produtos,
       array_agg(p.id order by p.created_at)    as product_ids,
       array_agg(p.color order by p.created_at) as colors
  from products p
 where p.status <> 'arquivado'
 group by 1
having count(*) > 1;

-- Relatório interno: não deve ser legível pelos papéis públicos.
revoke all on color_merge_candidates from anon, authenticated;
