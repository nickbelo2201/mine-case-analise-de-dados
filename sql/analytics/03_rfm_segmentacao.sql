-- Pergunta: quem são as melhores clientes, e quem está sumindo?
-- Técnicas: RFM com NTILE, data de corte = última venda da base (não now(),
-- para o resultado ser reprodutível), CASE para regras de segmento,
-- janela sobre agregado para % da receita.
-- Só funciona porque o cliente é único por WhatsApp normalizado (ver 013_customers.sql):
-- sem isso, a mesma pessoa viraria 3 clientes e a frequência seria subestimada.
WITH base AS (
  SELECT customer_id,
         MAX(created_at)  AS ultima_compra,
         COUNT(*)         AS frequencia,
         SUM(total_cents) AS valor
    FROM vw_vendas
   WHERE customer_id IS NOT NULL
   GROUP BY customer_id
),
corte AS (
  SELECT MAX(created_at) AS data_corte FROM vw_vendas
),
score AS (
  SELECT b.*,
         EXTRACT(DAY FROM c.data_corte - b.ultima_compra)::INT AS recencia_dias,
         NTILE(5) OVER (ORDER BY b.ultima_compra)              AS r,
         NTILE(5) OVER (ORDER BY b.frequencia, b.valor)        AS f,
         NTILE(5) OVER (ORDER BY b.valor)                      AS m
    FROM base b CROSS JOIN corte c
),
segmento AS (
  SELECT *,
         CASE
           WHEN r >= 4 AND f >= 4 THEN '1. Campeãs'
           WHEN r >= 3 AND f >= 3 THEN '2. Leais'
           WHEN r >= 4 AND f <= 2 THEN '3. Novas / promissoras'
           WHEN r <= 2 AND f >= 4 THEN '4. Em risco (eram boas)'
           WHEN r <= 2 AND f <= 2 THEN '6. Hibernando'
           ELSE                        '5. Precisam de atenção'
         END AS segmento
    FROM score
)
SELECT segmento,
       COUNT(*)                                                   AS clientes,
       ROUND(AVG(recencia_dias))                                  AS recencia_media_dias,
       ROUND(AVG(frequencia), 1)                                  AS compras_media,
       ROUND(AVG(valor) / 100.0, 2)                               AS valor_medio_rs,
       ROUND(SUM(valor) / 100.0, 2)                               AS receita_rs,
       ROUND(100.0 * SUM(valor) / SUM(SUM(valor)) OVER (), 1)     AS pct_receita
  FROM segmento
 GROUP BY segmento
 ORDER BY segmento;
