-- Pergunta: quais produtos sustentam a loja? (Pareto / curva ABC)
-- Técnicas: soma acumulada com window frame explícito, classificação por faixa.
-- Receita no grão de item = preço unitário congelado × quantidade (antes do desconto do pedido).
WITH produto AS (
  SELECT produto, categoria,
         SUM(qtd)           AS pecas,
         SUM(receita_cents) AS receita,
         SUM(receita_cents - custo_cents) AS margem
    FROM vw_itens_vendidos
   GROUP BY produto, categoria
),
acumulado AS (
  SELECT *,
         100.0 * SUM(receita) OVER (ORDER BY receita DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
               / SUM(receita) OVER () AS pct_acumulado,
         ROW_NUMBER() OVER (ORDER BY receita DESC) AS posicao
    FROM produto
)
SELECT posicao,
       produto,
       categoria,
       pecas,
       ROUND(receita / 100.0, 2)            AS receita_rs,
       ROUND(100.0 * margem / receita, 1)   AS margem_pct,
       ROUND(pct_acumulado, 1)              AS pct_acumulado,
       CASE WHEN pct_acumulado <= 80 THEN 'A'
            WHEN pct_acumulado <= 95 THEN 'B'
            ELSE 'C' END                    AS classe
  FROM acumulado
 ORDER BY posicao;
