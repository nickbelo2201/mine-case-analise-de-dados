-- Pergunta: qual canal dá mais dinheiro de verdade, depois de desconto, custo e taxa?
-- Técnicas: ROLLUP para subtotal, custo congelado no item (snapshot), taxa de maquininha.
-- É a mesma separação que o financeiro do app faz entre "vendi" e "recebo de verdade".
SELECT COALESCE(canal, 'TOTAL')                                        AS canal,
       COUNT(*)                                                        AS vendas,
       ROUND(SUM(subtotal_cents) / 100.0, 2)                           AS receita_bruta_rs,
       ROUND(SUM(discount_cents) / 100.0, 2)                           AS descontos_rs,
       ROUND(SUM(shipping_cents) / 100.0, 2)                           AS frete_rs,
       ROUND(SUM(total_cents) / 100.0, 2)                              AS receita_liquida_rs,
       ROUND(SUM(cost_cents) / 100.0, 2)                               AS cmv_rs,
       ROUND(SUM(fee_cents) / 100.0, 2)                                AS taxas_rs,
       ROUND((SUM(total_cents) - SUM(cost_cents) - SUM(fee_cents)) / 100.0, 2) AS margem_contrib_rs,
       ROUND(100.0 * (SUM(total_cents) - SUM(cost_cents) - SUM(fee_cents)) / SUM(total_cents), 1)
                                                                       AS margem_pct
  FROM vw_vendas
 GROUP BY ROLLUP (canal)
 ORDER BY GROUPING(canal), receita_liquida_rs DESC;
