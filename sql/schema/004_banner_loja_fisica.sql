-- Slot do 2º banner do hero: chamada para a loja física (preto e branco)
insert into banners (slot, image_url) values
  ('hero_loja_fisica', '/images/hero-loja-fisica.webp')
on conflict (slot) do nothing;
