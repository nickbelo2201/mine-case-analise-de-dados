-- Pergunta: das clientes que compraram pela primeira vez em cada mês,
-- quantas voltaram 1, 2, 3 e 6 meses depois?
-- Técnicas: coorte por mês de primeira compra, diferença de meses em aritmética
-- inteira, pivot com COUNT(DISTINCT) FILTER. Célula que ainda não aconteceu
-- (coorte recente demais para ter "mês 6") sai como NULL, não como 0%.
WITH compras AS (
  SELECT customer_id, DATE_TRUNC('month', created_at)::DATE AS mes
    FROM vw_vendas
   WHERE customer_id IS NOT NULL
   GROUP BY 1, 2
),
primeira AS (
  SELECT customer_id, MIN(mes) AS coorte FROM compras GROUP BY 1
),
atividade AS (
  SELECT p.coorte,
         c.customer_id,
         (EXTRACT(YEAR FROM c.mes) * 12 + EXTRACT(MONTH FROM c.mes))
       - (EXTRACT(YEAR FROM p.coorte) * 12 + EXTRACT(MONTH FROM p.coorte)) AS m
    FROM compras c JOIN primeira p USING (customer_id)
),
ultimo AS (
  SELECT MAX(mes) AS mes FROM compras
),
pivot AS (
  SELECT a.coorte,
         (EXTRACT(YEAR FROM u.mes) * 12 + EXTRACT(MONTH FROM u.mes))
       - (EXTRACT(YEAR FROM a.coorte) * 12 + EXTRACT(MONTH FROM a.coorte)) AS meses_observados,
         COUNT(DISTINCT customer_id) FILTER (WHERE m = 0)  AS n0,
         COUNT(DISTINCT customer_id) FILTER (WHERE m = 1)  AS n1,
         COUNT(DISTINCT customer_id) FILTER (WHERE m = 2)  AS n2,
         COUNT(DISTINCT customer_id) FILTER (WHERE m = 3)  AS n3,
         COUNT(DISTINCT customer_id) FILTER (WHERE m = 6)  AS n6,
         COUNT(DISTINCT customer_id) FILTER (WHERE m >= 1) AS n_voltou
    FROM atividade a CROSS JOIN ultimo u
   GROUP BY a.coorte, u.mes
)
SELECT TO_CHAR(coorte, 'YYYY-MM')                                          AS coorte,
       n0                                                                  AS clientes_novas,
       CASE WHEN meses_observados >= 1 THEN ROUND(100.0 * n1 / n0, 1) END  AS m1_pct,
       CASE WHEN meses_observados >= 2 THEN ROUND(100.0 * n2 / n0, 1) END  AS m2_pct,
       CASE WHEN meses_observados >= 3 THEN ROUND(100.0 * n3 / n0, 1) END  AS m3_pct,
       CASE WHEN meses_observados >= 6 THEN ROUND(100.0 * n6 / n0, 1) END  AS m6_pct,
       ROUND(100.0 * n_voltou / n0, 1)                                     AS voltou_ate_hoje_pct
  FROM pivot
 ORDER BY coorte;
