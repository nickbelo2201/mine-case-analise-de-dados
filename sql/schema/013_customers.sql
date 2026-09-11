-- ============================================================
-- 013 — Clientes.
--
-- Chave real do cliente no varejo brasileiro é o WhatsApp. Ele é
-- guardado normalizado (E.164, só dígitos com DDI) — sem isso,
-- "(11) 98888-7777", "11988887777" e "5511988887777" viram três
-- clientes e o histórico se fragmenta.
--
-- `contacts` (funil WhatsApp/n8n) continua existindo e separado;
-- a ponte entre os dois é o número normalizado.
-- ============================================================

CREATE OR REPLACE FUNCTION normalize_phone(raw TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
DECLARE
  d TEXT;
BEGIN
  IF raw IS NULL THEN RETURN NULL; END IF;
  d := REGEXP_REPLACE(raw, '[^0-9]', '', 'g');
  IF d = '' THEN RETURN NULL; END IF;

  -- 10 ou 11 dígitos = número nacional sem DDI; assume Brasil.
  IF LENGTH(d) IN (10, 11) THEN
    d := '55' || d;
  END IF;

  RETURN d;
END $fn$;

CREATE TABLE IF NOT EXISTS customers (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  whatsapp      TEXT NOT NULL UNIQUE,   -- normalizado por normalize_phone
  email         TEXT,
  cpf           TEXT,
  birthdate     DATE,
  -- Manequim e preferências: tudo opcional, preenchido aos poucos.
  -- { "blusa": "M", "calca": "40", "gosta": "...", "evita": "..." }
  measurements  JSONB NOT NULL DEFAULT '{}',
  tags          TEXT[] NOT NULL DEFAULT '{}',
  notes         TEXT,
  accepts_marketing BOOLEAN NOT NULL DEFAULT FALSE,
  source        TEXT,                   -- 'site' | 'loja' | 'whatsapp' | 'importado'
  anonymized_at TIMESTAMPTZ,            -- LGPD: anonimiza, nunca apaga
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- whatsapp já ganha índice pelo unique da coluna
CREATE INDEX IF NOT EXISTS customers_name_idx      ON customers(name);
CREATE INDEX IF NOT EXISTS customers_birthdate_idx ON customers(birthdate);

DO $do$ BEGIN
  ALTER TABLE orders
    ADD CONSTRAINT orders_customer_fk
    FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL; END $do$;

ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "customers_service_only" ON customers;
CREATE POLICY "customers_service_only"
  ON customers FOR ALL
  USING (auth.role() = 'service_role');

-- ------------------------------------------------------------
-- upsert_customer — usado pelo checkout e pelo PDV.
-- Encontra pelo WhatsApp normalizado ou cria; nunca duplica.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION upsert_customer(
  p_name     TEXT,
  p_whatsapp TEXT,
  p_source   TEXT DEFAULT 'site'
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_phone TEXT := normalize_phone(p_whatsapp);
  v_id    UUID;
BEGIN
  IF v_phone IS NULL THEN RETURN NULL; END IF;

  INSERT INTO customers (name, whatsapp, source)
  VALUES (COALESCE(NULLIF(TRIM(p_name), ''), 'Cliente ' || RIGHT(v_phone, 4)), v_phone, p_source)
  ON CONFLICT (whatsapp) DO UPDATE
    SET name       = CASE WHEN customers.name LIKE 'Cliente %'
                            AND NULLIF(TRIM(p_name), '') IS NOT NULL
                          THEN p_name ELSE customers.name END,
        updated_at = NOW()
  RETURNING id INTO v_id;

  RETURN v_id;
END $fn$;

-- ------------------------------------------------------------
-- Visão consolidada: compras do site + do balcão na mesma ficha.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW customer_stats AS
SELECT c.id                                            AS customer_id,
       COUNT(o.id) FILTER (WHERE o.status NOT IN ('cancelado'))          AS compras,
       COALESCE(SUM(o.total_cents) FILTER (
         WHERE o.status IN ('confirmado','pago','enviado','entregue')), 0)::INT AS total_gasto_cents,
       MAX(o.created_at) FILTER (WHERE o.status <> 'cancelado')          AS ultima_compra
  FROM customers c
  LEFT JOIN orders o ON o.customer_id = c.id
 GROUP BY c.id;

-- Dado de cliente nunca é público.
REVOKE ALL ON customers      FROM anon, authenticated;
REVOKE ALL ON customer_stats FROM anon, authenticated;
