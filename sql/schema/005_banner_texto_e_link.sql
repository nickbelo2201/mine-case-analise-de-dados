-- Controle de texto sobreposto e link do banner
-- show_text = false: a imagem já traz a escrita, não renderiza texto por cima
ALTER TABLE banners ADD COLUMN IF NOT EXISTS show_text BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE banners ADD COLUMN IF NOT EXISTS title      TEXT;
ALTER TABLE banners ADD COLUMN IF NOT EXISTS subtitle   TEXT;
ALTER TABLE banners ADD COLUMN IF NOT EXISTS cta        TEXT;
-- destino do clique na imagem (ex.: /camisa para linkar a categoria Camisa)
ALTER TABLE banners ADD COLUMN IF NOT EXISTS link_url   TEXT;
