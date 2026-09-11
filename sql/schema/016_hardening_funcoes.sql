-- ============================================================
-- 016 — Fecha a superfície das funções internas.
--
-- Achado pelo linter de segurança do Supabase depois de aplicar a 009-015.
--
-- O Supabase concede EXECUTE em funções de `public` para `anon` e
-- `authenticated` por padrão, e elas ficam acessíveis em /rest/v1/rpc/.
-- Como as funções de estoque, pedido e senha são SECURITY DEFINER, isso
-- deixava qualquer pessoa com a chave pública do site (que vai no bundle
-- do navegador) chamar `set_admin_password` e tomar a conta da dona, ou
-- chamar `apply_stock_movement` e zerar o estoque.
--
-- O app sempre usa a service role, que não é afetada por estes revokes.
-- ============================================================

REVOKE ALL ON FUNCTION
  apply_stock_movement(UUID, INT, TEXT, TEXT, UUID, TEXT, TEXT),
  reserve_stock(UUID, INT, TEXT),
  release_stock(UUID, INT),
  commit_reservation(UUID, INT, TEXT, TEXT, UUID, TEXT),
  check_stock_integrity(),
  release_expired_reservations(),
  upsert_customer(TEXT, TEXT, TEXT),
  set_admin_password(TEXT, TEXT),
  verify_admin_password(TEXT, TEXT),
  sync_product_sizes()
FROM public, anon, authenticated;

-- Helpers puros: sem efeito colateral, mas também não precisam ser públicos.
REVOKE ALL ON FUNCTION
  unaccent_fallback(TEXT),
  slugify(TEXT),
  parse_price_cents(TEXT),
  normalize_phone(TEXT)
FROM public, anon, authenticated;

-- search_path fixo: sem isso, um schema no caminho do chamador pode
-- sequestrar as chamadas feitas dentro da função.
ALTER FUNCTION unaccent_fallback(TEXT)     SET search_path = public;
ALTER FUNCTION slugify(TEXT)               SET search_path = public;
ALTER FUNCTION parse_price_cents(TEXT)     SET search_path = public;
ALTER FUNCTION normalize_phone(TEXT)       SET search_path = public;
ALTER FUNCTION sync_product_sizes()        SET search_path = public;
ALTER FUNCTION check_stock_integrity()     SET search_path = public;

-- A view pública de variantes foi criada por precaução na 009 e nunca é
-- usada: o app lê tudo com a service role. Uma view SECURITY DEFINER sem
-- uso é só superfície de ataque a mais. Se um dia o site passar a ler com
-- a chave anônima, ela volta — desenhada junto com a política de leitura.
DROP VIEW IF EXISTS product_variants_public;
