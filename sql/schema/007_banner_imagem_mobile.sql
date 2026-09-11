-- Versão retrato (Android/mobile) dos banners primários do hero
-- Recomendado: 1080 x 1350px (proporção 4:5)
ALTER TABLE banners ADD COLUMN IF NOT EXISTS image_url_mobile TEXT;
