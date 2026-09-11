-- ============================================================
-- 012 — Pedidos de verdade.
--
-- As tabelas `orders` e `order_items` existem desde a 001 mas nunca
-- foram usadas pelo app. Aqui elas passam a ser o registro do pedido
-- que nasce no checkout do site (antes de abrir o WhatsApp) e do
-- pedido lançado à mão pela dona.
-- ============================================================

-- ------------------------------------------------------------
-- orders
-- ------------------------------------------------------------
ALTER TABLE orders ALTER COLUMN contact_id DROP NOT NULL;

ALTER TABLE orders ADD COLUMN IF NOT EXISTS channel         TEXT NOT NULL DEFAULT 'site';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_id     UUID;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS subtotal_cents  INT  NOT NULL DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS discount_cents  INT  NOT NULL DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS shipping_cents  INT  NOT NULL DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS total_cents     INT  NOT NULL DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_method  TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_status  TEXT NOT NULL DEFAULT 'pendente';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS tracking_code   TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS carrier         TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_name   TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_phone  TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS shipping_address JSONB;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS reserved_until  TIMESTAMPTZ;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS confirmed_at    TIMESTAMPTZ;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS cancelled_at    TIMESTAMPTZ;

-- Número legível para a dona e para a cliente ("pedido #1042").
CREATE SEQUENCE IF NOT EXISTS orders_number_seq START 1000;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS order_number INT;
UPDATE orders SET order_number = NEXTVAL('orders_number_seq') WHERE order_number IS NULL;
ALTER TABLE orders ALTER COLUMN order_number SET DEFAULT NEXTVAL('orders_number_seq');
ALTER TABLE orders ALTER COLUMN order_number SET NOT NULL;

DO $do$ BEGIN
  CREATE UNIQUE INDEX orders_number_key ON orders(order_number);
EXCEPTION WHEN duplicate_table THEN NULL; END $do$;

-- Status: o antigo tinha 4 valores; o novo cobre o ciclo real.
UPDATE orders SET status = CASE status
  WHEN 'pending'   THEN 'aguardando'
  WHEN 'confirmed' THEN 'confirmado'
  WHEN 'delivered' THEN 'entregue'
  WHEN 'cancelled' THEN 'cancelado'
  ELSE status
END;

ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE orders ADD CONSTRAINT orders_status_check CHECK (status IN (
  'aguardando', 'confirmado', 'pago', 'enviado', 'entregue', 'cancelado', 'devolvido'
));
ALTER TABLE orders ALTER COLUMN status SET DEFAULT 'aguardando';

DO $do$ BEGIN
  ALTER TABLE orders ADD CONSTRAINT orders_channel_check
    CHECK (channel IN ('site', 'loja', 'whatsapp'));
EXCEPTION WHEN duplicate_object THEN NULL; END $do$;

DO $do$ BEGIN
  ALTER TABLE orders ADD CONSTRAINT orders_payment_status_check
    CHECK (payment_status IN ('pendente', 'pago', 'estornado'));
EXCEPTION WHEN duplicate_object THEN NULL; END $do$;

CREATE INDEX IF NOT EXISTS orders_channel_idx     ON orders(channel);
CREATE INDEX IF NOT EXISTS orders_created_at_idx  ON orders(created_at DESC);
CREATE INDEX IF NOT EXISTS orders_reserved_idx    ON orders(reserved_until)
  WHERE status = 'aguardando';

-- ------------------------------------------------------------
-- order_items — o item congela o que foi vendido e a que custo.
-- Mudar o preço do produto amanhã não pode alterar o pedido de hoje
-- nem a margem histórica.
-- ------------------------------------------------------------
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS variant_id            UUID REFERENCES product_variants(id) ON DELETE RESTRICT;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS unit_price_cents      INT;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS cost_cents_snapshot   INT NOT NULL DEFAULT 0;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS product_name_snapshot TEXT;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS size_snapshot         TEXT;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS color_snapshot        TEXT;

-- Backfill do que já existia (a coluna antiga unit_price é numeric em reais).
UPDATE order_items SET unit_price_cents = ROUND(unit_price * 100)::INT
 WHERE unit_price_cents IS NULL;
UPDATE order_items SET size_snapshot = size WHERE size_snapshot IS NULL;

CREATE INDEX IF NOT EXISTS order_items_variant_idx ON order_items(variant_id);

-- ------------------------------------------------------------
-- order_events — histórico de status: quem mudou o quê e quando.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS order_events (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id    UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  from_status TEXT,
  to_status   TEXT NOT NULL,
  note        TEXT,
  created_by  TEXT NOT NULL DEFAULT 'sistema',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS order_events_order_idx ON order_events(order_id, created_at DESC);

ALTER TABLE order_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "order_events_service_only" ON order_events;
CREATE POLICY "order_events_service_only"
  ON order_events FOR ALL
  USING (auth.role() = 'service_role');

-- ------------------------------------------------------------
-- release_expired_reservations — devolve ao estoque o que ficou
-- reservado em pedido que ninguém confirmou. Roda por cron/job.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION release_expired_reservations()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_order RECORD;
  v_item  RECORD;
  v_count INT := 0;
BEGIN
  FOR v_order IN
    SELECT id, status FROM orders
     WHERE status = 'aguardando'
       AND reserved_until IS NOT NULL
       AND reserved_until < NOW()
     FOR UPDATE SKIP LOCKED
  LOOP
    FOR v_item IN
      SELECT variant_id, quantity FROM order_items
       WHERE order_id = v_order.id AND variant_id IS NOT NULL
    LOOP
      PERFORM release_stock(v_item.variant_id, v_item.quantity);
    END LOOP;

    UPDATE orders
       SET status = 'cancelado', cancelled_at = NOW()
     WHERE id = v_order.id;

    INSERT INTO order_events (order_id, from_status, to_status, note, created_by)
    VALUES (v_order.id, 'aguardando', 'cancelado',
            'Cancelado automaticamente: reserva expirou', 'sistema');

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END $fn$;

-- Pedidos já eram service-role-only na 001; o mesmo vale para os eventos.
REVOKE ALL ON order_events FROM anon, authenticated;
