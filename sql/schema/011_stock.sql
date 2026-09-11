-- ============================================================
-- 011 — Estoque: movimentações e as funções que são a ÚNICA porta
--       de escrita do saldo.
--
-- Regra do sistema: nenhum código de aplicação faz UPDATE em
-- stock_on_hand ou stock_reserved. Tudo passa por estas funções,
-- que gravam o movimento e ajustam o saldo na mesma transação.
-- ============================================================

CREATE TABLE IF NOT EXISTS stock_movements (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  variant_id  UUID NOT NULL REFERENCES product_variants(id) ON DELETE RESTRICT,
  delta       INT  NOT NULL CHECK (delta <> 0),   -- + entrada / − saída
  reason      TEXT NOT NULL CHECK (reason IN (
                'venda_online', 'venda_loja', 'devolucao', 'perda', 'ajuste',
                'entrada_compra', 'inventario', 'transferencia', 'mostruario'
              )),
  -- Origem do movimento: 'order' / 'pos_sale' / 'purchase' / 'inventory'
  ref_type    TEXT,
  ref_id      UUID,
  note        TEXT,
  created_by  TEXT NOT NULL DEFAULT 'sistema',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS stock_movements_variant_idx ON stock_movements(variant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS stock_movements_reason_idx  ON stock_movements(reason);
CREATE INDEX IF NOT EXISTS stock_movements_created_idx ON stock_movements(created_at DESC);

-- Idempotência: um mesmo pedido não pode baixar o mesmo item duas vezes.
CREATE UNIQUE INDEX IF NOT EXISTS stock_movements_ref_unique
  ON stock_movements(ref_type, ref_id, variant_id, reason)
  WHERE ref_id IS NOT NULL;

ALTER TABLE stock_movements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "stock_movements_service_only" ON stock_movements;
CREATE POLICY "stock_movements_service_only"
  ON stock_movements FOR ALL
  USING (auth.role() = 'service_role');

-- ------------------------------------------------------------
-- apply_stock_movement — grava o movimento e ajusta o saldo.
-- Recusa se levaria o saldo a negativo, exceto em 'ajuste'/'inventario',
-- onde o número contado é a verdade (mas nunca abaixo de zero).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION apply_stock_movement(
  p_variant_id UUID,
  p_delta      INT,
  p_reason     TEXT,
  p_ref_type   TEXT DEFAULT NULL,
  p_ref_id     UUID DEFAULT NULL,
  p_note       TEXT DEFAULT NULL,
  p_by         TEXT DEFAULT 'sistema'
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_id  UUID;
  v_new INT;
BEGIN
  IF p_delta = 0 THEN
    RAISE EXCEPTION 'Movimento de estoque com quantidade zero.';
  END IF;

  -- Trava a linha para serializar movimentos concorrentes na mesma variante.
  SELECT stock_on_hand + p_delta INTO v_new
    FROM product_variants
   WHERE id = p_variant_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Variante % não encontrada.', p_variant_id;
  END IF;

  IF v_new < 0 THEN
    IF p_reason IN ('ajuste', 'inventario') THEN
      v_new := 0;
    ELSE
      RAISE EXCEPTION 'Estoque insuficiente: a operação deixaria o saldo negativo.'
        USING errcode = 'check_violation';
    END IF;
  END IF;

  UPDATE product_variants
     SET stock_on_hand = v_new,
         updated_at    = NOW()
   WHERE id = p_variant_id;

  INSERT INTO stock_movements (variant_id, delta, reason, ref_type, ref_id, note, created_by)
  VALUES (p_variant_id, p_delta, p_reason, p_ref_type, p_ref_id, p_note, p_by)
  RETURNING id INTO v_id;

  RETURN v_id;
END $fn$;

-- ------------------------------------------------------------
-- reserve_stock — a trava anti-oversell.
-- O UPDATE condicional é atômico: se afetou 0 linhas, não havia saldo.
-- Nunca lê o saldo na aplicação para depois gravar.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION reserve_stock(
  p_variant_id UUID,
  p_qty        INT,
  p_channel    TEXT DEFAULT 'site'
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_safety INT := 0;
  v_rows   INT;
BEGIN
  IF p_qty <= 0 THEN
    RAISE EXCEPTION 'Quantidade inválida para reserva.';
  END IF;

  IF p_channel = 'site' THEN
    SELECT site_safety_stock INTO v_safety FROM store_settings WHERE id = 1;
  END IF;

  UPDATE product_variants v
     SET stock_reserved = v.stock_reserved + p_qty,
         updated_at     = NOW()
    FROM products p
   WHERE v.id = p_variant_id
     AND p.id = v.product_id
     AND v.active
     AND (p_channel <> 'site' OR p.status = 'ativo')
     AND v.stock_on_hand - v.stock_reserved - COALESCE(v_safety, 0) >= p_qty;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows > 0;
END $fn$;

-- ------------------------------------------------------------
-- release_stock — devolve a reserva (pedido cancelado ou expirado).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION release_stock(
  p_variant_id UUID,
  p_qty        INT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  UPDATE product_variants
     SET stock_reserved = GREATEST(stock_reserved - p_qty, 0),
         updated_at     = NOW()
   WHERE id = p_variant_id;
END $fn$;

-- ------------------------------------------------------------
-- commit_reservation — libera a reserva e aplica a saída definitiva,
-- numa transação só. Idempotente por (ref_type, ref_id, variante).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION commit_reservation(
  p_variant_id UUID,
  p_qty        INT,
  p_reason     TEXT,
  p_ref_type   TEXT,
  p_ref_id     UUID,
  p_by         TEXT DEFAULT 'sistema'
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_existing UUID;
BEGIN
  SELECT id INTO v_existing
    FROM stock_movements
   WHERE ref_type = p_ref_type AND ref_id = p_ref_id
     AND variant_id = p_variant_id AND reason = p_reason;

  IF v_existing IS NOT NULL THEN
    RETURN v_existing;   -- já baixado: clicar duas vezes não dobra nada
  END IF;

  PERFORM release_stock(p_variant_id, p_qty);
  RETURN apply_stock_movement(
    p_variant_id, -p_qty, p_reason, p_ref_type, p_ref_id, NULL, p_by
  );
END $fn$;

-- ------------------------------------------------------------
-- check_stock_integrity — rede de segurança contra bug de código.
-- A soma das movimentações tem que bater com o saldo materializado.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION check_stock_integrity()
RETURNS TABLE (
  variant_id     UUID,
  sku            TEXT,
  saldo_atual    INT,
  soma_movimentos INT,
  divergencia    INT
)
LANGUAGE SQL
STABLE
AS $fn$
  SELECT v.id,
         v.sku,
         v.stock_on_hand,
         COALESCE(m.total, 0)::INT,
         v.stock_on_hand - COALESCE(m.total, 0)::INT
    FROM product_variants v
    LEFT JOIN (
      SELECT variant_id, SUM(delta) AS total
        FROM stock_movements
       GROUP BY variant_id
    ) m ON m.variant_id = v.id
   WHERE v.stock_on_hand <> COALESCE(m.total, 0);
$fn$;

-- ------------------------------------------------------------
-- Lançamento inicial: o saldo que veio da migração precisa existir
-- como movimento, senão a conferência de integridade acusa tudo.
-- ------------------------------------------------------------
INSERT INTO stock_movements (variant_id, delta, reason, ref_type, ref_id, note, created_by)
SELECT v.id, v.stock_on_hand, 'inventario', 'migration',
       '00000000-0000-0000-0000-000000000010'::UUID,
       'Saldo inicial migrado do cadastro antigo', 'migracao'
  FROM product_variants v
 WHERE v.stock_on_hand > 0
ON CONFLICT DO NOTHING;

-- O histórico de estoque é interno.
REVOKE ALL ON stock_movements FROM anon, authenticated;
