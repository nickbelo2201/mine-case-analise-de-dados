-- Conteúdo editável do site.
--
-- Uma linha por seção da vitrine (`key`), com os campos daquela seção em
-- `value`. O formato é jsonb porque cada seção tem campos diferentes e eles
-- mudam junto com o layout — uma coluna por texto viraria uma migration a
-- cada ajuste de copy, que é exatamente o problema que esta tabela resolve.
--
-- Linha ausente = o site usa o padrão de fábrica de `src/data/content.ts`.
-- Por isso não há seed aqui: no dia do deploy a vitrine continua idêntica.

CREATE TABLE IF NOT EXISTS site_content (
  key         TEXT PRIMARY KEY,
  value       JSONB NOT NULL DEFAULT '{}'::JSONB,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by  TEXT
);

ALTER TABLE site_content ENABLE ROW LEVEL SECURITY;

-- Mesma dupla de policies dos banners: a vitrine lê, só o service role escreve.
DROP POLICY IF EXISTS "site_content_public_read" ON site_content;
DROP POLICY IF EXISTS "site_content_service_write" ON site_content;

CREATE POLICY "site_content_public_read" ON site_content FOR SELECT USING (TRUE);
CREATE POLICY "site_content_service_write" ON site_content FOR ALL USING (auth.role() = 'service_role');
