-- Pergunta: como a receita evolui mês a mês, e quanto dela já vem do online?
-- Técnicas: CTE, agregação condicional (FILTER), window functions (LAG, média móvel).
-- Observação: date_trunc em timestamptz respeita o fuso da sessão (America/Sao_Paulo);
-- sem isso, uma venda às 22h do dia 31 cairia no mês seguinte.
WITH mensal AS (
  SELECT DATE_TRUNC('month', created_at)::DATE                     AS mes,
         SUM(total_cents)                                         AS total,
         SUM(total_cents) FILTER (WHERE canal = 'loja')           AS loja,
         SUM(total_cents) FILTER (WHERE canal IN ('site', 'whatsapp')) AS online,
         COUNT(*)                                                 AS vendas
    FROM vw_vendas
   GROUP BY 1
)
SELECT TO_CHAR(mes, 'YYYY-MM')                                          AS mes,
       ROUND(total / 100.0, 2)                                          AS receita_rs,
       vendas,
       ROUND(total / 100.0 / vendas, 2)                                 AS ticket_medio_rs,
       ROUND(100.0 * online / total, 1)                                 AS pct_online,
       ROUND(100.0 * (total - LAG(total) OVER w) / LAG(total) OVER w, 1) AS var_mom_pct,
       ROUND(AVG(total) OVER (ORDER BY mes ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) / 100.0, 2)
                                                                        AS media_movel_3m_rs
  FROM mensal
WINDOW w AS (ORDER BY mes)
 ORDER BY mes;
