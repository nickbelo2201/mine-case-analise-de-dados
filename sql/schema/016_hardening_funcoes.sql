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

revoke all on function
  apply_stock_movement(uuid, int, text, text, uuid, text, text),
  reserve_stock(uuid, int, text),
  release_stock(uuid, int),
  commit_reservation(uuid, int, text, text, uuid, text),
  check_stock_integrity(),
  release_expired_reservations(),
  upsert_customer(text, text, text),
  set_admin_password(text, text),
  verify_admin_password(text, text),
  sync_product_sizes()
from public, anon, authenticated;

-- Helpers puros: sem efeito colateral, mas também não precisam ser públicos.
revoke all on function
  unaccent_fallback(text),
  slugify(text),
  parse_price_cents(text),
  normalize_phone(text)
from public, anon, authenticated;

-- search_path fixo: sem isso, um schema no caminho do chamador pode
-- sequestrar as chamadas feitas dentro da função.
alter function unaccent_fallback(text)     set search_path = public;
alter function slugify(text)               set search_path = public;
alter function parse_price_cents(text)     set search_path = public;
alter function normalize_phone(text)       set search_path = public;
alter function sync_product_sizes()        set search_path = public;
alter function check_stock_integrity()     set search_path = public;

-- A view pública de variantes foi criada por precaução na 009 e nunca é
-- usada: o app lê tudo com a service role. Uma view SECURITY DEFINER sem
-- uso é só superfície de ataque a mais. Se um dia o site passar a ler com
-- a chave anônima, ela volta — desenhada junto com a política de leitura.
drop view if exists product_variants_public;
