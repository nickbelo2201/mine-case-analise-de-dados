-- Produtos podem pertencer a mais de uma categoria.
-- `category` continua sendo a categoria principal (tipo de peça);
-- `extra_categories` guarda slugs adicionais (ex.: luxo, casual, dia-a-dia).
ALTER TABLE products ADD COLUMN IF NOT EXISTS extra_categories TEXT[] NOT NULL DEFAULT '{}';
CREATE INDEX IF NOT EXISTS products_extra_categories_idx ON products USING gin (extra_categories);

-- Categorias de curadoria existem e têm página própria, mas ficam fora
-- do menu do topo e da grade de categorias da home.
ALTER TABLE categories ADD COLUMN IF NOT EXISTS show_in_nav BOOLEAN NOT NULL DEFAULT TRUE;

INSERT INTO categories (name, slug, parent_id, sort_order, active, show_in_nav)
VALUES
  ('Dia a Dia', 'dia-a-dia', NULL, 100, TRUE, FALSE),
  ('Casual',    'casual',    NULL, 101, TRUE, FALSE),
  ('Luxo',      'luxo',      NULL, 102, TRUE, FALSE)
ON CONFLICT (slug) DO NOTHING;
