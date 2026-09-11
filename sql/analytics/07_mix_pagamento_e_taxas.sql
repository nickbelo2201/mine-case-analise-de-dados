-- Pergunta: quanto a maquininha come do faturamento do balcão?
-- Técnicas: join com filtro de status, participação com window sobre agregado.
-- Pagamento dividido (PIX + cartão) é uma linha por forma em pos_payments,
-- por isso "transações" ≠ "vendas".
SELECT p.method                                                        AS forma,
       COUNT(*)                                                        AS transacoes,
       ROUND(SUM(p.amount_cents) / 100.0, 2)                           AS valor_rs,
       ROUND(100.0 * SUM(p.amount_cents) / SUM(SUM(p.amount_cents)) OVER (), 1) AS pct_valor,
       ROUND(AVG(p.installments) FILTER (WHERE p.method = 'credito_parcelado'), 1) AS parcelas_media,
       ROUND(SUM(p.fee_cents) / 100.0, 2)                              AS taxas_rs,
       ROUND(100.0 * SUM(p.fee_cents) / SUM(p.amount_cents), 2)        AS taxa_efetiva_pct
  FROM pos_payments p
  JOIN pos_sales s ON s.id = p.sale_id
 WHERE s.status = 'concluida'
 GROUP BY p.method
 ORDER BY valor_rs DESC;
