-- Versão retrato (Android/mobile) dos banners primários do hero
-- Recomendado: 1080 x 1350px (proporção 4:5)
alter table banners add column if not exists image_url_mobile text;
