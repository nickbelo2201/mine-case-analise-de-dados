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
UPDATE products
   SET price_cents = parse_price_cents(price)
 WHERE price_cents IS NULL;

-- ------------------------------------------------------------
-- 2. Slug único a partir de modelo + nome + cor
--    (a cor entra porque hoje cada cor é um produto separado;
--     depois da consolidação os slugs seguem válidos)
-- ------------------------------------------------------------
WITH base AS (
  SELECT id,
         NULLIF(slugify(CONCAT_WS('-', NULLIF(model, ''), name, NULLIF(color, ''))), '') AS s,
         ROW_NUMBER() OVER (
           PARTITION BY slugify(CONCAT_WS('-', NULLIF(model, ''), name, NULLIF(color, '')))
           ORDER BY created_at
         ) AS n
    FROM products
   WHERE slug IS NULL
)
UPDATE products p
   SET slug = CASE WHEN base.n = 1 THEN base.s
                   ELSE base.s || '-' || base.n END
  FROM base
 WHERE p.id = base.id
   AND base.s IS NOT NULL;

-- Qualquer produto sem nome aproveitável cai no id curto.
UPDATE products
   SET slug = 'produto-' || LEFT(id::TEXT, 8)
 WHERE slug IS NULL;

DO $do$ BEGIN
  CREATE UNIQUE INDEX products_slug_key ON products(slug);
EXCEPTION WHEN duplicate_table THEN NULL; END $do$;

-- ------------------------------------------------------------
-- 3. sizes JSONB -> linhas em product_variants
--    Cor da variante = products.color (o modelo antigo).
--    SKU = MODELO-COR-TAMANHO, com o id curto como desempate.
-- ------------------------------------------------------------
INSERT INTO product_variants (product_id, color, size, sku, stock_on_hand, price_cents, cost_cents)
SELECT p.id,
       COALESCE(p.color, ''),
       s.size,
       UPPER(CONCAT_WS('-',
         NULLIF(slugify(COALESCE(NULLIF(p.model, ''), p.name)), ''),
         NULLIF(slugify(COALESCE(p.color, '')), ''),
         slugify(s.size),
         LEFT(p.id::TEXT, 4)
       )),
       GREATEST(s.stock, 0),
       NULL,   -- herda o preço do produto
       0       -- custo desconhecido: a dona preenche ou vem da entrada de compra
  FROM products p
  CROSS JOIN LATERAL (
    SELECT item ->> 'size'                              AS size,
           COALESCE((item ->> 'stock')::INT, 0)         AS stock
      FROM JSONB_ARRAY_ELEMENTS(COALESCE(p.sizes, '[]'::JSONB)) AS item
     WHERE NULLIF(item ->> 'size', '') IS NOT NULL
  ) s
 ON CONFLICT (product_id, color, size) DO NOTHING;

-- ------------------------------------------------------------
-- 4. images text[] -> product_images preservando a ordem
--    A primeira imagem continua sendo a capa (sort_order = 0).
-- ------------------------------------------------------------
INSERT INTO product_images (product_id, url, sort_order, color)
SELECT p.id, img.url, img.ord - 1, COALESCE(p.color, '')
  FROM products p
  CROSS JOIN LATERAL UNNEST(COALESCE(p.images, '{}')) WITH ORDINALITY AS img(url, ord)
 WHERE NOT EXISTS (
   SELECT 1 FROM product_images pi
    WHERE pi.product_id = p.id AND pi.url = img.url
 );

-- ------------------------------------------------------------
-- 5. Produto sem preço válido não pode ficar "ativo" no site.
--    Vira rascunho e o admin mostra o motivo na tela.
-- ------------------------------------------------------------
UPDATE products
   SET status = 'rascunho'
 WHERE status = 'ativo'
   AND (price_cents IS NULL OR price_cents <= 0);

-- ------------------------------------------------------------
-- 6. Relatório de candidatos à consolidação de cores.
--    NÃO funde nada — a fusão é manual, revisada pela dona no admin.
--    Mesma peça (modelo + nome) cadastrada em cores diferentes.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW color_merge_candidates AS
SELECT slugify(CONCAT_WS('-', NULLIF(p.model, ''), p.name)) AS merge_key,
       MIN(p.model)                AS model,
       MIN(p.name)                 AS name,
       COUNT(*)                    AS produtos,
       ARRAY_AGG(p.id ORDER BY p.created_at)    AS product_ids,
       ARRAY_AGG(p.color ORDER BY p.created_at) AS colors
  FROM products p
 WHERE p.status <> 'arquivado'
 GROUP BY 1
HAVING COUNT(*) > 1;

-- Relatório interno: não deve ser legível pelos papéis públicos.
REVOKE ALL ON color_merge_candidates FROM anon, authenticated;
