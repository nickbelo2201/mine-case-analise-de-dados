-- Slot do 2º banner do hero: chamada para a loja física (preto e branco)
INSERT INTO banners (slot, image_url) VALUES
  ('hero_loja_fisica', '/images/hero-loja-fisica.webp')
ON CONFLICT (slot) DO NOTHING;
