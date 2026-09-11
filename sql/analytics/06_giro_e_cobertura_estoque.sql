-- Pergunta: onde tem dinheiro parado no estoque e onde vai faltar peça?
-- Técnicas: venda média diária dos últimos 90 dias a partir do ledger de estoque
-- (stock_movements), cobertura em dias, capital imobilizado a custo, NULLIF contra divisão por zero.
WITH corte AS (
  SELECT MAX(created_at) AS data_corte FROM stock_movements
),
saidas_90d AS (
  SELECT m.variant_id, -SUM(m.delta) AS vendidas
    FROM stock_movements m CROSS JOIN corte c
   WHERE m.reason IN ('venda_online', 'venda_loja')
     AND m.created_at > c.data_corte - INTERVAL '90 days'
   GROUP BY m.variant_id
),
detalhe AS (
  SELECT v.id,
         v.stock_on_hand                                                   AS estoque,
         COALESCE(s.vendidas, 0)                                           AS vendidas_90d,
         v.stock_on_hand * v.cost_cents                                    AS capital_cents,
         v.stock_on_hand / NULLIF(COALESCE(s.vendidas, 0) / 90.0, 0)       AS cobertura_dias
    FROM product_variants v
    LEFT JOIN saidas_90d s ON s.variant_id = v.id
   WHERE v.active
),
situacao AS (
  SELECT *,
         CASE
           WHEN estoque = 0 AND vendidas_90d > 0 THEN '1. Ruptura (vende e acabou)'
           WHEN cobertura_dias < 15              THEN '2. Repor em até 15 dias'
           WHEN vendidas_90d = 0 AND estoque > 0 THEN '5. Parado (0 vendas em 90 dias)'
           WHEN cobertura_dias > 120             THEN '4. Excesso (> 120 dias)'
           ELSE                                       '3. Saudável'
         END AS situacao
    FROM detalhe
)
SELECT situacao,
       COUNT(*)                              AS variantes,
       SUM(estoque)                          AS pecas,
       ROUND(SUM(capital_cents) / 100.0, 2)  AS capital_a_custo_rs,
       ROUND(100.0 * SUM(capital_cents) / SUM(SUM(capital_cents)) OVER (), 1) AS pct_capital,
       ROUND(AVG(cobertura_dias))            AS cobertura_media_dias
  FROM situacao
 GROUP BY situacao
 ORDER BY situacao;
