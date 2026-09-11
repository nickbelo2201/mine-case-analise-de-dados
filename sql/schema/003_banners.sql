CREATE TABLE IF NOT EXISTS banners (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slot        TEXT NOT NULL UNIQUE,
  image_url   TEXT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE banners ENABLE ROW LEVEL SECURITY;

CREATE POLICY "banners_public_read" ON banners FOR SELECT USING (TRUE);
CREATE POLICY "banners_service_write" ON banners FOR ALL USING (auth.role() = 'service_role');

INSERT INTO banners (slot, image_url) VALUES
  ('hero_nova_colecao',     '/images/hero-colecao-nova.png'),
  ('hero_estilo_proprio',   '/images/hero-estilo-proprio.png'),
  ('text_banner_luxo',      '/images/banner-nobre.webp'),
  ('text_banner_casual',    '/images/banner-ecologico.webp'),
  ('text_banner_dia_a_dia', '/images/hero-distincao-desktop.webp')
ON CONFLICT (slot) DO NOTHING;
