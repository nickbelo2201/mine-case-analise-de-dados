CREATE TABLE IF NOT EXISTS categories (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  slug        TEXT NOT NULL UNIQUE,
  parent_id   UUID REFERENCES categories(id) ON DELETE SET NULL,
  image_url   TEXT,
  sort_order  INT NOT NULL DEFAULT 0,
  active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS categories_slug_idx   ON categories(slug);
CREATE INDEX IF NOT EXISTS categories_parent_idx ON categories(parent_id);
CREATE INDEX IF NOT EXISTS categories_sort_idx   ON categories(sort_order);

ALTER TABLE categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "categories_public_read"
  ON categories FOR SELECT
  USING (TRUE);

CREATE POLICY "categories_service_write"
  ON categories FOR ALL
  USING (auth.role() = 'service_role');

INSERT INTO categories (name, slug, sort_order) VALUES
  ('Camisetas', 'camisetas', 1),
  ('Calças',    'calcas',    2),
  ('Bermudas',  'bermudas',  3),
  ('Moletons',  'moletons',  4),
  ('Jaquetas',  'jaquetas',  5)
ON CONFLICT (slug) DO NOTHING;
