-- Tag "Mais escolhida": marca no admin quais peças aparecem na seção
-- "Mais escolhidos" da home. No máximo 6, limite garantido pelo admin.
ALTER TABLE products ADD COLUMN IF NOT EXISTS is_featured BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS products_is_featured_idx ON products(is_featured);
