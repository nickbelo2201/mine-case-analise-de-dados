-- Controle de texto sobreposto e link do banner
-- show_text = false: a imagem já traz a escrita, não renderiza texto por cima
alter table banners add column if not exists show_text boolean not null default true;
alter table banners add column if not exists title      text;
alter table banners add column if not exists subtitle   text;
alter table banners add column if not exists cta        text;
-- destino do clique na imagem (ex.: /camisa para linkar a categoria Camisa)
alter table banners add column if not exists link_url   text;
