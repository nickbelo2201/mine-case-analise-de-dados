-- ============================================================
-- MINE - Schema inicial do banco de dados
-- ============================================================

-- Extensão para UUIDs
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- CATÁLOGO
-- ============================================================

CREATE TABLE IF NOT EXISTS products (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  model       TEXT NOT NULL DEFAULT '',
  color       TEXT NOT NULL DEFAULT '',
  category    TEXT NOT NULL,
  price       TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  images      TEXT[] NOT NULL DEFAULT '{}',
  sizes       JSONB NOT NULL DEFAULT '[]',
  in_promotion BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS products_category_idx ON products(category);
CREATE INDEX IF NOT EXISTS products_in_promotion_idx ON products(in_promotion);

-- ============================================================
-- FUNIL WHATSAPP
-- ============================================================

CREATE TABLE IF NOT EXISTS contacts (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  whatsapp_number   TEXT NOT NULL UNIQUE,
  name              TEXT,
  status            TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'active', 'customer', 'inactive')),
  tags              TEXT[] NOT NULL DEFAULT '{}',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_interaction  TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS contacts_whatsapp_idx ON contacts(whatsapp_number);
CREATE INDEX IF NOT EXISTS contacts_status_idx ON contacts(status);

CREATE TABLE IF NOT EXISTS messages (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id      UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  content         TEXT NOT NULL,
  direction       TEXT NOT NULL CHECK (direction IN ('inbound', 'outbound')),
  message_type    TEXT NOT NULL DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'template')),
  delivery_status TEXT NOT NULL DEFAULT 'sent' CHECK (delivery_status IN ('sent', 'delivered', 'read', 'failed')),
  metadata        JSONB DEFAULT '{}',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS messages_contact_idx ON messages(contact_id);
CREATE INDEX IF NOT EXISTS messages_created_at_idx ON messages(created_at DESC);

CREATE TABLE IF NOT EXISTS orders (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id  UUID NOT NULL REFERENCES contacts(id) ON DELETE RESTRICT,
  status      TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'delivered', 'cancelled')),
  notes       TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS orders_contact_idx ON orders(contact_id);
CREATE INDEX IF NOT EXISTS orders_status_idx ON orders(status);

CREATE TABLE IF NOT EXISTS order_items (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id    UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id  UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
  size        TEXT NOT NULL,
  quantity    INT NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_price  NUMERIC(10,2) NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS order_items_order_idx ON order_items(order_id);

-- ============================================================
-- CAMPANHAS
-- ============================================================

CREATE TABLE IF NOT EXISTS campaigns (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type             TEXT NOT NULL CHECK (type IN ('weekly', 'stock_clearance', 'birthday', 'custom')),
  message_template TEXT NOT NULL,
  scheduled_at     TIMESTAMPTZ,
  sent_at          TIMESTAMPTZ,
  status           TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'sent', 'failed')),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS campaign_contacts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id     UUID NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  contact_id      UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  sent_at         TIMESTAMPTZ,
  delivery_status TEXT DEFAULT 'pending',
  UNIQUE(campaign_id, contact_id)
);

CREATE INDEX IF NOT EXISTS campaign_contacts_campaign_idx ON campaign_contacts(campaign_id);

-- ============================================================
-- ANALYTICS
-- ============================================================

CREATE TABLE IF NOT EXISTS analytics_daily (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date                    DATE NOT NULL UNIQUE,
  site_visitors           INT NOT NULL DEFAULT 0,
  meta_ads_clicks         INT NOT NULL DEFAULT 0,
  meta_ads_impressions    INT NOT NULL DEFAULT 0,
  whatsapp_conversations  INT NOT NULL DEFAULT 0,
  orders_confirmed        INT NOT NULL DEFAULT 0,
  cpm                     NUMERIC(10,4),
  ctr                     NUMERIC(10,4),
  cpc                     NUMERIC(10,4),
  roas                    NUMERIC(10,4)
);

-- ============================================================
-- RLS (Row Level Security)
-- ============================================================

-- Habilitar RLS em todas as tabelas
ALTER TABLE products         ENABLE ROW LEVEL SECURITY;
ALTER TABLE contacts         ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages         ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders           ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items      ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaigns        ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics_daily  ENABLE ROW LEVEL SECURITY;

-- products: leitura pública (catálogo do site), escrita apenas via service role
CREATE POLICY "products_public_read"
  ON products FOR SELECT
  USING (TRUE);

CREATE POLICY "products_service_write"
  ON products FOR ALL
  USING (auth.role() = 'service_role');

-- Demais tabelas: apenas service role (acesso via n8n/API backend)
CREATE POLICY "contacts_service_only"
  ON contacts FOR ALL
  USING (auth.role() = 'service_role');

CREATE POLICY "messages_service_only"
  ON messages FOR ALL
  USING (auth.role() = 'service_role');

CREATE POLICY "orders_service_only"
  ON orders FOR ALL
  USING (auth.role() = 'service_role');

CREATE POLICY "order_items_service_only"
  ON order_items FOR ALL
  USING (auth.role() = 'service_role');

CREATE POLICY "campaigns_service_only"
  ON campaigns FOR ALL
  USING (auth.role() = 'service_role');

CREATE POLICY "campaign_contacts_service_only"
  ON campaign_contacts FOR ALL
  USING (auth.role() = 'service_role');

CREATE POLICY "analytics_service_only"
  ON analytics_daily FOR ALL
  USING (auth.role() = 'service_role');

-- ============================================================
-- STORAGE BUCKET para imagens de produtos
-- ============================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('product-images', 'product-images', TRUE)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "product_images_public_read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'product-images');

CREATE POLICY "product_images_service_write"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'product-images' AND auth.role() = 'service_role');

CREATE POLICY "product_images_service_delete"
  ON storage.objects FOR DELETE
  USING (bucket_id = 'product-images' AND auth.role() = 'service_role');
