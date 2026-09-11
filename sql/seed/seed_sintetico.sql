-- ============================================================
-- Seed sintético — 12 meses de operação (set/2025 a ago/2026).
--
-- NENHUM dado aqui é real. Os dados do cliente não saem do banco
-- de produção; este script gera uma base com o mesmo formato e
-- com comportamentos plausíveis de varejo de moda:
--   • sazonalidade (Black Friday, Natal, Dia das Mães) + tendência de alta;
--   • loja física fechada aos domingos, venda online a qualquer hora;
--   • clientes recorrentes com distribuição concentrada (poucos compram muito);
--   • produtos com popularidade desigual (base para a curva ABC);
--   • cancelamentos, devoluções e pedidos ainda em andamento no fim do período.
--
-- Tudo é set-based (generate_series + CTEs), sem loop, e reprodutível
-- via setseed. O estoque é lançado como movimentos em stock_movements,
-- de modo que check_stock_integrity() fecha em zero.
-- ============================================================

SELECT SETSEED(0.42);

-- ------------------------------------------------------------
-- 1. Catálogo: 5 categorias × modelos × 2 linhas (Essencial/Premium)
-- ------------------------------------------------------------
CREATE TEMP TABLE t_cat (cat TEXT, modelos TEXT[], preco_min INT, preco_max INT);
INSERT INTO t_cat VALUES
  ('camisetas', ARRAY['Camiseta Básica','Camiseta Oversized','Camiseta Estampada','Camiseta Gola V','Regata'], 5990, 11990),
  ('calcas',    ARRAY['Calça Jeans Reta','Calça Cargo','Calça Alfaiataria','Calça Jogger'],               12990, 24990),
  ('bermudas',  ARRAY['Bermuda Jeans','Bermuda Sarja','Bermuda Moletom'],                                 7990, 14990),
  ('moletons',  ARRAY['Moletom Canguru','Moletom Careca','Blusão Fleece'],                               14990, 25990),
  ('jaquetas',  ARRAY['Jaqueta Jeans','Jaqueta Corta-vento','Jaqueta Couro Eco','Bomber'],               19990, 36990);

INSERT INTO products (name, model, category, price, price_cents, status, slug, description, created_at)
SELECT nome,
       modelo,
       cat,
       'R$ ' || REPLACE(TO_CHAR(preco / 100.0, 'FM9990.00'), '.', ','),   -- formato legado (texto)
       preco,
       'ativo',
       slugify(nome),
       'Produto sintético para o case.',
       TIMESTAMPTZ '2025-08-01' + RANDOM() * INTERVAL '20 days'
  FROM (
    SELECT c.cat,
           m.modelo_nome || ' ' || l.linha                         AS nome,
           'MN-' || LPAD((ROW_NUMBER() OVER (ORDER BY c.cat, m.ord, l.linha))::TEXT, 3, '0') AS modelo,
           (ROUND(((c.preco_min + RANDOM() * (c.preco_max - c.preco_min)) * l.mult) / 1000) * 1000 - 10)::INT AS preco
      FROM t_cat c
      CROSS JOIN LATERAL UNNEST(c.modelos) WITH ORDINALITY m(modelo_nome, ord)
      CROSS JOIN (VALUES ('Essencial', 1.0), ('Premium', 1.45)) l(linha, mult)
  ) x;

-- Variantes: 2 cores por produto × grade P/M/G/GG. Custo congelado ~38-47% do preço.
INSERT INTO product_variants (product_id, color, size, sku, cost_cents, low_stock_threshold)
SELECT p.id,
       cor,
       tam,
       UPPER(p.model || '-' || slugify(cor) || '-' || tam),
       ROUND(p.price_cents * (0.38 + (ABS(HASHTEXT(p.model)) % 10) / 100.0))::INT,
       2
  FROM products p
  CROSS JOIN LATERAL (
    SELECT cor
      FROM UNNEST(ARRAY['Preto','Branco','Off-white','Azul Marinho','Verde Oliva','Caramelo']) cor
     WHERE p.id IS NOT NULL                      -- força reavaliação por produto
     ORDER BY RANDOM()
     LIMIT 2
  ) cores
  CROSS JOIN UNNEST(ARRAY['P','M','G','GG']) tam;

-- ------------------------------------------------------------
-- 2. Clientes: 700 pessoas fictícias com WhatsApp normalizado
-- ------------------------------------------------------------
CREATE TEMP TABLE t_cli AS
SELECT g AS n,
       gen_random_uuid() AS id,
       (ARRAY['Ana','Beatriz','Camila','Daniela','Eduarda','Fernanda','Gabriela','Helena','Isabela','Julia',
              'Lucas','Mateus','Pedro','Rafael','Thiago','Bruno','Gustavo','Felipe','Larissa','Mariana'])[1 + floor(RANDOM() * 20)::INT]
         || ' ' ||
       (ARRAY['Silva','Souza','Oliveira','Santos','Lima','Pereira','Costa','Almeida','Ferreira','Rocha'])[1 + floor(RANDOM() * 10)::INT] AS nome,
       -- Número determinístico e único por cliente, escrito "sujo" de propósito:
       -- normalize_phone é quem padroniza para E.164.
       format('(%s) 9%s-%s',
              (ARRAY['11','11','11','21','31','41','19'])[1 + (g % 7)],
              SUBSTR(LPAD(((g * 7919) % 100000000)::TEXT, 8, '0'), 1, 4),
              SUBSTR(LPAD(((g * 7919) % 100000000)::TEXT, 8, '0'), 5, 4)) AS whatsapp_bruto,
       (ARRAY['site','loja','whatsapp','loja'])[1 + floor(RANDOM() * 4)::INT] AS origem
  FROM GENERATE_SERIES(1, 2500) g;

INSERT INTO customers (id, name, whatsapp, source, accepts_marketing, created_at)
SELECT id, nome, normalize_phone(whatsapp_bruto), origem, RANDOM() < 0.6,
       TIMESTAMPTZ '2025-08-01' + RANDOM() * INTERVAL '390 days'
  FROM t_cli;

-- ------------------------------------------------------------
-- 3. Eventos de venda com sazonalidade e tendência
-- ------------------------------------------------------------
CREATE TEMP TABLE t_venda AS
WITH cand AS (
  SELECT TIMESTAMPTZ '2025-09-01 00:00:00-03' + RANDOM() * INTERVAL '365 days' AS ts,
         RANDOM() AS r_keep, RANDOM() AS r_canal, RANDOM() AS r_cli,
         RANDOM() AS r_status, RANDOM() AS r_desc, RANDOM() AS r_hora
    FROM GENERATE_SERIES(1, 11000)
),
filtrado AS (
  SELECT *,
         -- peso do mês × tendência de crescimento ao longo do ano
         (CASE EXTRACT(MONTH FROM ts at TIME ZONE 'America/Sao_Paulo')
            WHEN 12 THEN 1.00 WHEN 11 THEN 0.85 WHEN 5 THEN 0.78
            WHEN 1 THEN 0.42 WHEN 2 THEN 0.45 WHEN 3 THEN 0.50
            ELSE 0.58 END)
         * (0.70 + 0.60 * EXTRACT(EPOCH FROM ts - TIMESTAMPTZ '2025-09-01 00:00:00-03') / (365 * 86400)) AS peso
    FROM cand
),
canal AS (
  SELECT *,
         CASE WHEN r_canal < 0.42 THEN 'loja' WHEN r_canal < 0.86 THEN 'site' ELSE 'whatsapp' END AS canal0
    FROM filtrado
   WHERE r_keep < peso
)
SELECT ROW_NUMBER() OVER (ORDER BY ts) AS n,
       gen_random_uuid() AS id,
       -- loja: fecha domingo, horário comercial 9h-20h
       CASE WHEN canal0 = 'loja' AND EXTRACT(ISODOW FROM ts at TIME ZONE 'America/Sao_Paulo') = 7 THEN 'site'
            ELSE canal0 END AS canal,
       CASE WHEN canal0 = 'loja' AND EXTRACT(ISODOW FROM ts at TIME ZONE 'America/Sao_Paulo') <> 7
            THEN (DATE_TRUNC('day', ts at TIME ZONE 'America/Sao_Paulo') + INTERVAL '9 hours' + r_hora * INTERVAL '11 hours')
                   at TIME ZONE 'America/Sao_Paulo'
            ELSE ts END AS ts,
       -- 20% das vendas de loja e 5% das online sem cliente identificado.
       -- Das identificadas: 40% vêm de um núcleo fiel (~400 clientes, concentrado),
       -- 60% da base ampla (2.500 clientes, a maioria compra 1 ou 2 vezes).
       CASE WHEN (canal0 = 'loja' AND r_cli < 0.20) OR (canal0 <> 'loja' AND r_cli < 0.05) THEN NULL
            WHEN RANDOM() < 0.40 THEN 1 + floor(power(RANDOM(), 1.5) * 400)::INT
            ELSE 1 + floor(RANDOM() * 2500)::INT END AS cli_n,
       r_status, r_desc
  FROM canal;

-- ------------------------------------------------------------
-- 4. Itens: popularidade desigual de produto, grade com M/G mais vendidos
-- ------------------------------------------------------------
CREATE TEMP TABLE t_prod AS
SELECT id, ROW_NUMBER() OVER (ORDER BY RANDOM()) AS rk FROM products;

CREATE TEMP TABLE t_var AS
SELECT v.id, v.product_id, v.size, v.cost_cents, p.price_cents, p.name,
       DENSE_RANK() OVER (PARTITION BY v.product_id ORDER BY v.color) AS cor_n, v.color
  FROM product_variants v JOIN products p ON p.id = v.product_id;

CREATE TEMP TABLE t_linha AS
SELECT v.n, v.id AS venda_id, k,
       1 + floor(power(RANDOM(), 1.9) * (SELECT COUNT(*) FROM products))::INT AS prod_rk,
       CASE WHEN RANDOM() < 0.20 THEN 'P' WHEN RANDOM() < 0.45 THEN 'M'
            WHEN RANDOM() < 0.60 THEN 'G' ELSE 'GG' END AS tam,
       1 + (RANDOM() < 0.5)::INT AS cor_n,
       CASE WHEN RANDOM() < 0.9 THEN 1 ELSE 2 END AS qty
  FROM t_venda v
  CROSS JOIN LATERAL GENERATE_SERIES(1, 1 + (RANDOM() < 0.35 AND v.n > 0)::INT + (RANDOM() < 0.10)::INT) k;

-- Afinidade de cesta: metade dos 2º itens vem da categoria "par" do 1º
-- (calça → camiseta, camiseta → bermuda, jaqueta → moletom...).
UPDATE t_linha l2
   SET prod_rk = (
     SELECT tp.rk
       FROM t_prod tp JOIN products p ON p.id = tp.id
      WHERE p.category = (
              SELECT CASE p1.category
                       WHEN 'calcas'    THEN 'camisetas'
                       WHEN 'camisetas' THEN 'bermudas'
                       WHEN 'bermudas'  THEN 'camisetas'
                       WHEN 'jaquetas'  THEN 'moletons'
                       ELSE 'calcas' END
                FROM t_linha l1
                JOIN t_prod t1   ON t1.rk = l1.prod_rk
                JOIN products p1 ON p1.id = t1.id
               WHERE l1.venda_id = l2.venda_id AND l1.k = 1)
      ORDER BY RANDOM() + l2.k * 0
      LIMIT 1)
 WHERE l2.k = 2 AND RANDOM() < 0.5;

-- Peças de frio (moletom, jaqueta) puxam para G/GG.
UPDATE t_linha l
   SET tam = CASE WHEN RANDOM() < 0.10 THEN 'P' WHEN RANDOM() < 0.35 THEN 'M'
                  WHEN RANDOM() < 0.65 THEN 'G' ELSE 'GG' END
  FROM t_prod tp JOIN products p ON p.id = tp.id
 WHERE tp.rk = l.prod_rk AND p.category IN ('moletons', 'jaquetas');

CREATE TEMP TABLE t_item AS
SELECT l.venda_id, tv.id AS variant_id, tv.product_id, tv.name, tv.size, tv.color,
       l.qty, tv.price_cents AS unit_price_cents, tv.cost_cents
  FROM t_linha l
  JOIN t_prod tp ON tp.rk = l.prod_rk
  JOIN t_var  tv ON tv.product_id = tp.id AND tv.size = l.tam AND tv.cor_n = l.cor_n;

-- Totais por venda (10% de desconto em ~15% das vendas; frete grátis acima de R$ 299)
CREATE TEMP TABLE t_total AS
SELECT v.*,
       s.subtotal,
       CASE WHEN v.r_desc < 0.15 THEN ROUND(s.subtotal * 0.10)::INT ELSE 0 END AS desconto,
       CASE WHEN v.canal <> 'loja' AND s.subtotal < 29900 THEN 1990 ELSE 0 END AS frete,
       s.custo
  FROM t_venda v
  JOIN (SELECT venda_id,
               SUM(unit_price_cents * qty)::INT AS subtotal,
               SUM(cost_cents * qty)::INT       AS custo
          FROM t_item GROUP BY venda_id) s ON s.venda_id = v.id;

-- ------------------------------------------------------------
-- 5. Pedidos online (site + WhatsApp)
-- ------------------------------------------------------------
INSERT INTO orders (id, channel, customer_id, status, subtotal_cents, discount_cents, shipping_cents,
                    total_cents, payment_method, payment_status, customer_name, customer_phone,
                    created_at, updated_at, confirmed_at, cancelled_at, reserved_until)
SELECT t.id, t.canal, c.id,
       st.status,
       t.subtotal, t.desconto, t.frete, t.subtotal - t.desconto + t.frete,
       CASE WHEN t.r_desc < 0.55 THEN 'pix' ELSE 'cartao' END,
       CASE st.status WHEN 'aguardando' THEN 'pendente' WHEN 'cancelado' THEN 'pendente'
                      WHEN 'devolvido' THEN 'estornado' ELSE 'pago' END,
       c.nome, normalize_phone(c.whatsapp_bruto),
       t.ts, t.ts,
       CASE WHEN st.status NOT IN ('aguardando', 'cancelado') THEN t.ts + INTERVAL '2 hours' END,
       CASE WHEN st.status = 'cancelado' THEN t.ts + INTERVAL '2 days' END,
       t.ts + INTERVAL '48 hours'
  FROM t_total t
  LEFT JOIN t_cli c ON c.n = t.cli_n
  CROSS JOIN LATERAL (
    SELECT CASE
             WHEN t.ts > TIMESTAMPTZ '2026-08-25' THEN
               (ARRAY['aguardando','pago','enviado'])[1 + floor(t.r_status * 3)::INT]
             WHEN t.r_status < 0.07 THEN 'cancelado'
             WHEN t.r_status < 0.10 THEN 'devolvido'
             ELSE 'entregue'
           END AS status
  ) st
 WHERE t.canal <> 'loja';

INSERT INTO order_items (order_id, product_id, variant_id, size, quantity, unit_price, unit_price_cents,
                         cost_cents_snapshot, product_name_snapshot, size_snapshot, color_snapshot, created_at)
SELECT i.venda_id, i.product_id, i.variant_id, i.size, i.qty, i.unit_price_cents / 100.0, i.unit_price_cents,
       i.cost_cents, i.name, i.size, i.color, o.created_at
  FROM t_item i JOIN orders o ON o.id = i.venda_id;

-- Histórico de status (order_events): base do lead time de entrega
INSERT INTO order_events (order_id, from_status, to_status, created_at, created_by)
SELECT o.id, e.de, e.para, o.created_at + e.depois, 'seed'
  FROM orders o
  CROSS JOIN LATERAL (
    SELECT NULL::TEXT AS de, 'aguardando' AS para, INTERVAL '0' AS depois
    UNION ALL SELECT 'aguardando', 'confirmado', INTERVAL '2 hours'
     WHERE o.status NOT IN ('aguardando', 'cancelado')
    UNION ALL SELECT 'aguardando', 'cancelado', INTERVAL '2 days'
     WHERE o.status = 'cancelado'
    UNION ALL SELECT 'confirmado', 'enviado', INTERVAL '1 day' + (ABS(HASHTEXT(o.order_number::TEXT)) % 48) * INTERVAL '1 hour'
     WHERE o.status IN ('enviado', 'entregue', 'devolvido')
    UNION ALL SELECT 'enviado', 'entregue', INTERVAL '4 days' + (ABS(HASHTEXT(o.order_number::TEXT)) % 120) * INTERVAL '1 hour'
     WHERE o.status IN ('entregue', 'devolvido')
    UNION ALL SELECT 'entregue', 'devolvido', INTERVAL '12 days'
     WHERE o.status = 'devolvido'
  ) e;

-- ------------------------------------------------------------
-- 6. PDV: sessões de caixa por dia, vendas, itens e pagamentos
-- ------------------------------------------------------------
INSERT INTO cash_sessions (id, opened_by, opened_at, opening_cents, closed_by, closed_at)
SELECT gen_random_uuid(), 'Vendedora A', dia + INTERVAL '8 hours 45 minutes', 20000,
       'Vendedora A', dia + INTERVAL '20 hours 15 minutes'
  FROM (SELECT DISTINCT DATE_TRUNC('day', ts at TIME ZONE 'America/Sao_Paulo') at TIME ZONE 'America/Sao_Paulo' AS dia
          FROM t_total WHERE canal = 'loja') d;

INSERT INTO pos_sales (id, session_id, customer_id, seller, subtotal_cents, discount_cents, total_cents,
                       cost_cents, status, cancelled_at, cancelled_by, cancel_reason, created_at)
SELECT t.id, cs.id, c.id,
       (ARRAY['Vendedora A','Vendedora B','Vendedora C'])[1 + (t.n % 3)::INT],
       t.subtotal, t.desconto, t.subtotal - t.desconto, t.custo,
       CASE WHEN t.r_status < 0.02 THEN 'cancelada' ELSE 'concluida' END,
       CASE WHEN t.r_status < 0.02 THEN t.ts + INTERVAL '10 minutes' END,
       CASE WHEN t.r_status < 0.02 THEN 'Vendedora A' END,
       CASE WHEN t.r_status < 0.02 THEN 'Cliente desistiu no caixa' END,
       t.ts
  FROM t_total t
  LEFT JOIN t_cli c ON c.n = t.cli_n
  JOIN cash_sessions cs
    ON DATE_TRUNC('day', cs.opened_at at TIME ZONE 'America/Sao_Paulo')
     = DATE_TRUNC('day', t.ts at TIME ZONE 'America/Sao_Paulo')
 WHERE t.canal = 'loja';

INSERT INTO pos_sale_items (sale_id, variant_id, quantity, unit_price_cents, cost_cents_snapshot,
                            product_name_snapshot, size_snapshot, color_snapshot)
SELECT i.venda_id, i.variant_id, i.qty, i.unit_price_cents, i.cost_cents, i.name, i.size, i.color
  FROM t_item i JOIN pos_sales s ON s.id = i.venda_id;

-- Um pagamento por venda; ~12% dividem em dois (metade PIX + restante cartão).
-- Taxa da maquininha: débito 1,5% · crédito 3,2% · parcelado 4,9% · PIX/dinheiro 0.
WITH base AS (
  SELECT s.id, s.total_cents, RANDOM() AS r_div, RANDOM() AS r_met, RANDOM() AS r_parc
    FROM pos_sales s WHERE s.total_cents > 0
),
partes AS (
  SELECT id, CASE WHEN r_div < 0.12 THEN 'pix'
                  WHEN r_met < 0.30 THEN 'pix'
                  WHEN r_met < 0.45 THEN 'debito'
                  WHEN r_met < 0.70 THEN 'credito'
                  WHEN r_met < 0.90 THEN 'credito_parcelado'
                  ELSE 'dinheiro' END AS metodo,
         CASE WHEN r_div < 0.12 THEN total_cents / 2 ELSE total_cents END AS valor,
         r_parc
    FROM base
  UNION ALL
  SELECT id, 'credito', total_cents - total_cents / 2, r_parc
    FROM base WHERE r_div < 0.12
)
INSERT INTO pos_payments (sale_id, method, amount_cents, installments, fee_cents, brand)
SELECT id, metodo, valor,
       CASE WHEN metodo = 'credito_parcelado' THEN 2 + floor(r_parc * 5)::INT ELSE 1 END,
       ROUND(valor * CASE metodo WHEN 'debito' THEN 0.015 WHEN 'credito' THEN 0.032
                                 WHEN 'credito_parcelado' THEN 0.049 ELSE 0 END)::INT,
       CASE WHEN metodo IN ('debito','credito','credito_parcelado')
            THEN (ARRAY['Visa','Mastercard','Elo'])[1 + floor(r_parc * 3)::INT] END
  FROM partes;

-- ------------------------------------------------------------
-- 7. Estoque: saídas por venda + entrada inicial que cobre tudo
--    (movimentos gravados com a data real da venda → base do giro)
-- ------------------------------------------------------------
INSERT INTO stock_movements (variant_id, delta, reason, ref_type, ref_id, created_by, created_at)
SELECT i.variant_id, -SUM(i.quantity)::INT, 'venda_online', 'order', o.id, 'seed', o.confirmed_at
  FROM orders o JOIN order_items i ON i.order_id = o.id
 WHERE o.status IN ('confirmado','pago','enviado','entregue','devolvido')
 GROUP BY i.variant_id, o.id, o.confirmed_at
UNION ALL
SELECT i.variant_id, SUM(i.quantity)::INT, 'devolucao', 'order', o.id, 'seed', o.created_at + INTERVAL '12 days'
  FROM orders o JOIN order_items i ON i.order_id = o.id
 WHERE o.status = 'devolvido'
 GROUP BY i.variant_id, o.id, o.created_at
UNION ALL
SELECT i.variant_id, -SUM(i.quantity)::INT, 'venda_loja', 'pos_sale', s.id, 'seed', s.created_at
  FROM pos_sales s JOIN pos_sale_items i ON i.sale_id = s.id
 WHERE s.status = 'concluida'
 GROUP BY i.variant_id, s.id, s.created_at;

-- Entrada de compra que cobre as vendas + sobra aleatória (0 a 8 peças).
-- Algumas variantes terminam zeradas (ruptura), outras encalhadas.
INSERT INTO stock_movements (variant_id, delta, reason, ref_type, note, created_by, created_at)
SELECT v.id,
       COALESCE(-m.saidas, 0) + floor(RANDOM() * 9)::INT + (CASE WHEN m.saidas IS NULL THEN 3 ELSE 0 END),
       'entrada_compra', 'purchase', 'Estoque inicial sintético', 'seed', TIMESTAMPTZ '2025-08-25'
  FROM product_variants v
  LEFT JOIN (SELECT variant_id, SUM(delta) AS saidas FROM stock_movements GROUP BY variant_id) m
    ON m.variant_id = v.id
 WHERE COALESCE(-m.saidas, 0) + floor(RANDOM() * 9)::INT + (CASE WHEN m.saidas IS NULL THEN 3 ELSE 0 END) > 0;

-- Saldo materializado = soma dos movimentos
UPDATE product_variants v
   SET stock_on_hand = m.total
  FROM (SELECT variant_id, SUM(delta)::INT AS total FROM stock_movements GROUP BY variant_id) m
 WHERE m.variant_id = v.id;

-- Reservas dos pedidos ainda aguardando pagamento
UPDATE product_variants v
   SET stock_reserved = LEAST(r.qtd, v.stock_on_hand)
  FROM (SELECT i.variant_id, SUM(i.quantity)::INT AS qtd
          FROM orders o JOIN order_items i ON i.order_id = o.id
         WHERE o.status = 'aguardando' GROUP BY i.variant_id) r
 WHERE r.variant_id = v.id;

-- Cliente não pode ter sido "criado" depois da primeira compra
UPDATE customers c
   SET created_at = LEAST(c.created_at, f.primeira)
  FROM (SELECT customer_id, MIN(created_at) AS primeira FROM (
          SELECT customer_id, created_at FROM orders WHERE customer_id IS NOT NULL
          UNION ALL
          SELECT customer_id, created_at FROM pos_sales WHERE customer_id IS NOT NULL) u
        GROUP BY customer_id) f
 WHERE f.customer_id = c.id;

DROP TABLE t_cat, t_cli, t_venda, t_prod, t_var, t_linha, t_item, t_total;
