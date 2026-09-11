-- ============================================================
-- 014 — PDV (venda de balcão), caixa, usuários com papel e auditoria.
-- ============================================================

-- ------------------------------------------------------------
-- Usuários do admin — senha com hash, não mais em variável de ambiente
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS admin_users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email         TEXT NOT NULL UNIQUE,
  name          TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  role          TEXT NOT NULL DEFAULT 'vendedora'
                  CHECK (role IN ('dona', 'vendedora', 'estoquista')),
  active        BOOLEAN NOT NULL DEFAULT TRUE,
  last_login_at TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_users_service_only" ON admin_users;
CREATE POLICY "admin_users_service_only"
  ON admin_users FOR ALL
  USING (auth.role() = 'service_role');

CREATE OR REPLACE FUNCTION set_admin_password(p_email TEXT, p_plain TEXT)
RETURNS VOID
LANGUAGE SQL
SECURITY DEFINER
SET search_path = public, extensions
AS $fn$
  UPDATE admin_users
     SET password_hash = crypt(p_plain, gen_salt('bf', 10))
   WHERE LOWER(email) = LOWER(p_email);
$fn$;

CREATE OR REPLACE FUNCTION verify_admin_password(p_email TEXT, p_plain TEXT)
RETURNS TABLE (id UUID, email TEXT, name TEXT, role TEXT)
LANGUAGE SQL
SECURITY DEFINER
SET search_path = public, extensions
AS $fn$
  SELECT u.id, u.email, u.name, u.role
    FROM admin_users u
   WHERE LOWER(u.email) = LOWER(p_email)
     AND u.active
     AND u.password_hash = crypt(p_plain, u.password_hash);
$fn$;

-- ------------------------------------------------------------
-- Auditoria — quem fez o quê, quando, valor antes/depois.
-- Obrigatória em estoque, preço, desconto, cancelamento e exclusão.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_log (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor       TEXT NOT NULL,
  action      TEXT NOT NULL,          -- 'update' | 'delete' | 'cancel' | 'discount' | ...
  entity      TEXT NOT NULL,          -- 'product' | 'variant' | 'order' | 'pos_sale' | ...
  entity_id   UUID,
  before      JSONB,
  after       JSONB,
  note        TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS audit_log_entity_idx  ON audit_log(entity, entity_id, created_at DESC);
CREATE INDEX IF NOT EXISTS audit_log_created_idx ON audit_log(created_at DESC);

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "audit_log_service_only" ON audit_log;
CREATE POLICY "audit_log_service_only"
  ON audit_log FOR ALL
  USING (auth.role() = 'service_role');

-- ------------------------------------------------------------
-- Caixa
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cash_sessions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  opened_by       TEXT NOT NULL,
  opened_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  opening_cents   INT  NOT NULL DEFAULT 0,   -- fundo de troco
  closed_by       TEXT,
  closed_at       TIMESTAMPTZ,
  counted_cents   INT,                       -- dinheiro contado na gaveta
  expected_cents  INT,                       -- o que o sistema esperava
  difference_cents INT,
  note            TEXT
);

CREATE INDEX IF NOT EXISTS cash_sessions_open_idx ON cash_sessions(closed_at)
  WHERE closed_at IS NULL;

-- Sangria e suprimento
CREATE TABLE IF NOT EXISTS cash_movements (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id  UUID NOT NULL REFERENCES cash_sessions(id) ON DELETE CASCADE,
  kind        TEXT NOT NULL CHECK (kind IN ('sangria', 'suprimento')),
  amount_cents INT NOT NULL CHECK (amount_cents > 0),
  reason      TEXT,
  created_by  TEXT NOT NULL DEFAULT 'sistema',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- Vendas de balcão
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pos_sales (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_number     INT,
  session_id      UUID REFERENCES cash_sessions(id) ON DELETE SET NULL,
  customer_id     UUID REFERENCES customers(id) ON DELETE SET NULL,
  seller          TEXT NOT NULL,
  subtotal_cents  INT NOT NULL DEFAULT 0,
  discount_cents  INT NOT NULL DEFAULT 0,
  total_cents     INT NOT NULL DEFAULT 0,
  cost_cents      INT NOT NULL DEFAULT 0,   -- CMV congelado da venda
  status          TEXT NOT NULL DEFAULT 'concluida'
                    CHECK (status IN ('concluida', 'cancelada')),
  cancelled_by    TEXT,
  cancelled_at    TIMESTAMPTZ,
  cancel_reason   TEXT,
  discount_authorized_by TEXT,              -- quem liberou desconto acima do teto
  note            TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE SEQUENCE IF NOT EXISTS pos_sales_number_seq START 1;
ALTER TABLE pos_sales ALTER COLUMN sale_number SET DEFAULT NEXTVAL('pos_sales_number_seq');

CREATE INDEX IF NOT EXISTS pos_sales_created_idx  ON pos_sales(created_at DESC);
CREATE INDEX IF NOT EXISTS pos_sales_session_idx  ON pos_sales(session_id);
CREATE INDEX IF NOT EXISTS pos_sales_customer_idx ON pos_sales(customer_id);

CREATE TABLE IF NOT EXISTS pos_sale_items (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id               UUID NOT NULL REFERENCES pos_sales(id) ON DELETE CASCADE,
  variant_id            UUID NOT NULL REFERENCES product_variants(id) ON DELETE RESTRICT,
  quantity              INT  NOT NULL CHECK (quantity > 0),
  unit_price_cents      INT  NOT NULL,
  discount_cents        INT  NOT NULL DEFAULT 0,
  cost_cents_snapshot   INT  NOT NULL DEFAULT 0,
  product_name_snapshot TEXT,
  size_snapshot         TEXT,
  color_snapshot        TEXT
);

CREATE INDEX IF NOT EXISTS pos_sale_items_sale_idx ON pos_sale_items(sale_id);

-- Pagamento dividido: metade PIX, metade cartão.
-- A taxa da maquininha fica registrada aqui, senão o "faturamento" mente 3-5%.
CREATE TABLE IF NOT EXISTS pos_payments (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id       UUID NOT NULL REFERENCES pos_sales(id) ON DELETE CASCADE,
  method        TEXT NOT NULL CHECK (method IN (
                  'dinheiro', 'pix', 'debito', 'credito', 'credito_parcelado', 'vale_troca'
                )),
  amount_cents  INT NOT NULL CHECK (amount_cents > 0),
  installments  INT NOT NULL DEFAULT 1,
  fee_cents     INT NOT NULL DEFAULT 0,
  brand         TEXT
);

CREATE INDEX IF NOT EXISTS pos_payments_sale_idx ON pos_payments(sale_id);

ALTER TABLE cash_sessions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE cash_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_sales      ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_payments   ENABLE ROW LEVEL SECURITY;

DO $do$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['cash_sessions','cash_movements','pos_sales','pos_sale_items','pos_payments']
  LOOP
    EXECUTE format('drop policy if exists %I on %I', t || '_service_only', t);
    EXECUTE format(
      'create policy %I on %I for all using (auth.role() = ''service_role'')',
      t || '_service_only', t
    );
  END LOOP;
END $do$;

-- Nada aqui é público: vendas, caixa, usuários e auditoria.
REVOKE ALL ON admin_users, audit_log, cash_sessions, cash_movements,
              pos_sales, pos_sale_items, pos_payments
         FROM anon, authenticated;
