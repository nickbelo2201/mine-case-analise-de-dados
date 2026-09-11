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
CREATE TABLE IF NOT EXISTS store_settings (
  id                  INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  -- Colchão anti-oversell: quantas peças NUNCA são oferecidas no site,
  -- ficando reservadas para a venda no balcão.
  site_safety_stock   INT NOT NULL DEFAULT 1 CHECK (site_safety_stock >= 0),
  -- Desconto acima deste percentual exige senha da dona no PDV.
  pos_discount_limit  NUMERIC(5,2) NOT NULL DEFAULT 15,
  -- Minutos até a reserva de um pedido não confirmado expirar.
  reservation_minutes INT NOT NULL DEFAULT 2880,
  store_name          TEXT NOT NULL DEFAULT 'MineClothes',
  whatsapp_number     TEXT NOT NULL DEFAULT '5511900000000',  -- número fictício no case
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO store_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

ALTER TABLE store_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "store_settings_service_only" ON store_settings;
CREATE POLICY "store_settings_service_only"
  ON store_settings FOR ALL
  USING (auth.role() = 'service_role');

-- ------------------------------------------------------------
-- Colunas novas em products
-- ------------------------------------------------------------
ALTER TABLE products ADD COLUMN IF NOT EXISTS price_cents         INT;
ALTER TABLE products ADD COLUMN IF NOT EXISTS compare_price_cents INT;
ALTER TABLE products ADD COLUMN IF NOT EXISTS slug                TEXT;
ALTER TABLE products ADD COLUMN IF NOT EXISTS status              TEXT NOT NULL DEFAULT 'ativo';
ALTER TABLE products ADD COLUMN IF NOT EXISTS size_grid           TEXT NOT NULL DEFAULT 'letra';
ALTER TABLE products ADD COLUMN IF NOT EXISTS updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE products ADD COLUMN IF NOT EXISTS archived_at         TIMESTAMPTZ;

DO $do$ BEGIN
  ALTER TABLE products ADD CONSTRAINT products_status_check
    CHECK (status IN ('rascunho', 'ativo', 'arquivado'));
EXCEPTION WHEN duplicate_object THEN NULL; END $do$;

DO $do$ BEGIN
  ALTER TABLE products ADD CONSTRAINT products_size_grid_check
    CHECK (size_grid IN ('letra', 'numerica', 'unico', 'infantil'));
EXCEPTION WHEN duplicate_object THEN NULL; END $do$;

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------

-- Remove acentos sem depender da extensão `unaccent`.
CREATE OR REPLACE FUNCTION unaccent_fallback(raw TEXT)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $fn$
  SELECT TRANSLATE(
    COALESCE(raw, ''),
    'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ',
    'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN'
  );
$fn$;

-- "Camisa Básica" -> "camisa-basica"
CREATE OR REPLACE FUNCTION slugify(raw TEXT)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $fn$
  SELECT TRIM(BOTH '-' FROM REGEXP_REPLACE(
    LOWER(unaccent_fallback(raw)),
    '[^a-z0-9]+', '-', 'g'
  ));
$fn$;

-- "R$ 89,90" -> 8990 ; "1.299,00" -> 129900 ; "89.90" -> 8990
CREATE OR REPLACE FUNCTION parse_price_cents(raw TEXT)
RETURNS INT
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
DECLARE
  cleaned TEXT;
BEGIN
  IF raw IS NULL THEN RETURN NULL; END IF;

  cleaned := REGEXP_REPLACE(raw, '[^0-9,.]', '', 'g');
  IF cleaned = '' THEN RETURN NULL; END IF;

  -- Formato brasileiro: ponto separa milhar, vírgula separa decimal.
  IF position(',' IN cleaned) > 0 THEN
    cleaned := REPLACE(cleaned, '.', '');
    cleaned := REPLACE(cleaned, ',', '.');
  END IF;

  RETURN ROUND(cleaned::NUMERIC * 100)::INT;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END $fn$;

-- ------------------------------------------------------------
-- Variantes: a unidade real de estoque
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS product_variants (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id          UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  color               TEXT NOT NULL DEFAULT '',
  size                TEXT NOT NULL,
  sku                 TEXT UNIQUE,
  barcode             TEXT,
  stock_on_hand       INT  NOT NULL DEFAULT 0 CHECK (stock_on_hand >= 0),
  stock_reserved      INT  NOT NULL DEFAULT 0 CHECK (stock_reserved >= 0),
  low_stock_threshold INT  NOT NULL DEFAULT 2,
  -- null = herda o preço do produto
  price_cents         INT,
  cost_cents          INT  NOT NULL DEFAULT 0,
  active              BOOLEAN NOT NULL DEFAULT TRUE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (product_id, color, size)
);

CREATE INDEX IF NOT EXISTS product_variants_product_idx ON product_variants(product_id);
CREATE INDEX IF NOT EXISTS product_variants_barcode_idx ON product_variants(barcode);
CREATE INDEX IF NOT EXISTS product_variants_active_idx  ON product_variants(active);

-- ------------------------------------------------------------
-- Fotos: com ordem e vínculo opcional de cor
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS product_images (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id  UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  url         TEXT NOT NULL,
  sort_order  INT  NOT NULL DEFAULT 0,
  color       TEXT NOT NULL DEFAULT '',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS product_images_product_idx ON product_images(product_id, sort_order);

-- ------------------------------------------------------------
-- Disponibilidade — o site NUNCA lê stock_on_hand direto.
--
-- ATENÇÃO: esta view expõe `cost_cents` e por isso NÃO pode ser legível
-- pelos papéis públicos. O app sempre a consulta com a service role.
-- Para leitura pública existe `product_variants_public`, mais abaixo, que
-- não traz custo nem saldo bruto.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW product_variants_available AS
SELECT
  v.*,
  GREATEST(v.stock_on_hand - v.stock_reserved - s.site_safety_stock, 0) AS available_site,
  GREATEST(v.stock_on_hand - v.stock_reserved, 0)                       AS available_loja,
  COALESCE(v.price_cents, p.price_cents)                                AS effective_price_cents,
  p.status                                                              AS product_status,
  p.name                                                                AS product_name,
  p.slug                                                                AS product_slug
FROM product_variants v
JOIN products p ON p.id = v.product_id
CROSS JOIN store_settings s
WHERE s.id = 1;

-- ------------------------------------------------------------
-- Leitura pública sem dado sensível.
--
-- Só o que a vitrine precisa: o que dá para comprar e por quanto.
-- Custo, saldo real e reservas ficam de fora.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW product_variants_public AS
SELECT
  v.id,
  v.product_id,
  v.color,
  v.size,
  GREATEST(v.stock_on_hand - v.stock_reserved - s.site_safety_stock, 0) AS available_site,
  COALESCE(v.price_cents, p.price_cents) AS price_cents
FROM product_variants v
JOIN products p ON p.id = v.product_id
CROSS JOIN store_settings s
WHERE s.id = 1
  AND v.active
  AND p.status = 'ativo';

-- ------------------------------------------------------------
-- RLS
-- ------------------------------------------------------------
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_images   ENABLE ROW LEVEL SECURITY;

-- Sem leitura pública na tabela: ela carrega cost_cents.
DROP POLICY IF EXISTS "product_variants_public_read"  ON product_variants;
DROP POLICY IF EXISTS "product_variants_service_write" ON product_variants;
CREATE POLICY "product_variants_service_only"
  ON product_variants FOR ALL USING (auth.role() = 'service_role');

-- Views no Postgres rodam com os direitos do dono e ignoram a RLS da tabela
-- base, então não basta tirar a política: o acesso precisa ser revogado.
-- No Supabase, `anon` e `authenticated` ganham SELECT por padrão.
REVOKE ALL ON product_variants            FROM anon, authenticated;
REVOKE ALL ON product_variants_available  FROM anon, authenticated;
GRANT SELECT ON product_variants_public   TO anon, authenticated;

DROP POLICY IF EXISTS "product_images_public_read"  ON product_images;
DROP POLICY IF EXISTS "product_images_service_write" ON product_images;
CREATE POLICY "product_images_public_read"
  ON product_images FOR SELECT USING (TRUE);
CREATE POLICY "product_images_service_write"
  ON product_images FOR ALL USING (auth.role() = 'service_role');

-- ------------------------------------------------------------
-- Sincronia reversa: products.sizes é mantido a partir das variantes
-- enquanto o site público ainda o lê. A coluna sai na etapa 10.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION sync_product_sizes()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $fn$
DECLARE
  pid UUID := COALESCE(NEW.product_id, OLD.product_id);
BEGIN
  UPDATE products p
     SET sizes = COALESCE((
           SELECT JSONB_AGG(JSONB_BUILD_OBJECT('size', t.size, 'stock', t.stock)
                            ORDER BY t.ord, t.size)
             FROM (
               SELECT v.size,
                      SUM(v.stock_on_hand)::INT AS stock,
                      MIN(COALESCE(ARRAY_POSITION(
                        ARRAY['PP','P','M','G','GG','XGG'], v.size), 99)) AS ord
                 FROM product_variants v
                WHERE v.product_id = pid AND v.active
             GROUP BY v.size
             ) t
         ), '[]'::JSONB),
         updated_at = NOW()
   WHERE p.id = pid;
  RETURN NULL;
END $fn$;

DROP TRIGGER IF EXISTS product_variants_sync_sizes ON product_variants;
CREATE TRIGGER product_variants_sync_sizes
  AFTER INSERT OR UPDATE OR DELETE ON product_variants
  FOR EACH ROW EXECUTE FUNCTION sync_product_sizes();
