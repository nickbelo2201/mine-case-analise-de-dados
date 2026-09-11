-- Pergunta: quais categorias saem juntas? (vitrine, combos, "compre junto")
-- Técnicas: market basket analysis com self-join — suporte, confiança e lift.
-- lift > 1 → as duas aparecem juntas mais do que o acaso explicaria.
WITH cesta AS (
  SELECT DISTINCT venda_id, categoria FROM vw_itens_vendidos
),
total AS (
  SELECT COUNT(DISTINCT venda_id)::NUMERIC AS n FROM cesta
),
suporte AS (
  SELECT categoria, COUNT(*) AS vendas FROM cesta GROUP BY categoria
),
pares AS (
  SELECT a.categoria AS cat_a, b.categoria AS cat_b, COUNT(*) AS juntas
    FROM cesta a
    JOIN cesta b ON a.venda_id = b.venda_id AND a.categoria < b.categoria
   GROUP BY 1, 2
)
SELECT cat_a || ' + ' || cat_b                              AS par,
       juntas                                               AS vendas_juntas,
       ROUND(100.0 * juntas / t.n, 2)                       AS suporte_pct,
       ROUND(100.0 * juntas / sa.vendas, 1)                 AS confianca_a_para_b_pct,
       ROUND(juntas * t.n / (sa.vendas * sb.vendas), 2)     AS lift
  FROM pares
  JOIN suporte sa ON sa.categoria = cat_a
  JOIN suporte sb ON sb.categoria = cat_b
 CROSS JOIN total t
 ORDER BY lift DESC;
