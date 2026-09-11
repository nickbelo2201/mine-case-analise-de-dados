-- ============================================================
-- Camada analítica: uma venda é uma venda, venha de onde vier.
--
-- O modelo transacional tem dois fluxos com tabelas próprias:
--   orders / order_items        → site e WhatsApp (ciclo de status longo)
--   pos_sales / pos_sale_items  → balcão (venda nasce concluída, tem caixa e taxa)
-- Isso é o certo para operar, mas péssimo para analisar. Estas views
-- unificam os dois num grão único, com as mesmas regras de negócio
-- que o painel do admin usa (ver app-excerpts/supabase-dashboard.ts).
-- ============================================================

-- Regra de "vendido": pedido online conta a partir de confirmado;
-- devolvido e cancelado não entram na receita.
CREATE OR REPLACE VIEW vw_vendas AS
SELECT o.id                     AS venda_id,
       o.channel                AS canal,
       o.customer_id,
       o.created_at,
       o.subtotal_cents,
       o.discount_cents,
       o.shipping_cents,
       o.total_cents,
       COALESCE(i.custo, 0)     AS cost_cents,
       0                        AS fee_cents
  FROM orders o
  LEFT JOIN (SELECT order_id, SUM(cost_cents_snapshot * quantity)::INT AS custo
               FROM order_items GROUP BY order_id) i ON i.order_id = o.id
 WHERE o.status IN ('confirmado', 'pago', 'enviado', 'entregue')
UNION ALL
SELECT s.id,
       'loja',
       s.customer_id,
       s.created_at,
       s.subtotal_cents,
       s.discount_cents,
       0,
       s.total_cents,
       s.cost_cents,
       COALESCE(p.taxa, 0)
  FROM pos_sales s
  LEFT JOIN (SELECT sale_id, SUM(fee_cents)::INT AS taxa
               FROM pos_payments GROUP BY sale_id) p ON p.sale_id = s.id
 WHERE s.status = 'concluida';

-- Grão de item, já com categoria e produto do catálogo atual.
-- Nome/tamanho/cor vêm do snapshot congelado na venda.
CREATE OR REPLACE VIEW vw_itens_vendidos AS
SELECT v.venda_id,
       v.canal,
       v.customer_id,
       v.created_at,
       i.variant_id,
       pv.product_id,
       i.product_name_snapshot                   AS produto,
       p.category                                AS categoria,
       i.size_snapshot                           AS tamanho,
       i.color_snapshot                          AS cor,
       i.quantity                                AS qtd,
       i.unit_price_cents * i.quantity           AS receita_cents,
       i.cost_cents_snapshot * i.quantity        AS custo_cents
  FROM vw_vendas v
  JOIN (
    SELECT order_id AS venda_id, variant_id, product_name_snapshot, size_snapshot, color_snapshot,
           quantity, unit_price_cents, cost_cents_snapshot
      FROM order_items
    UNION ALL
    SELECT sale_id, variant_id, product_name_snapshot, size_snapshot, color_snapshot,
           quantity, unit_price_cents, cost_cents_snapshot
      FROM pos_sale_items
  ) i ON i.venda_id = v.venda_id
  JOIN product_variants pv ON pv.id = i.variant_id
  JOIN products p          ON p.id  = pv.product_id;

-- Views analíticas também não são públicas.
REVOKE ALL ON vw_vendas, vw_itens_vendidos FROM anon, authenticated;
