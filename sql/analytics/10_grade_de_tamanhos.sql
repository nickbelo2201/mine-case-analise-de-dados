-- Pergunta: na hora de comprar do fornecedor, qual a proporção de cada tamanho por categoria?
-- Técnicas: pivot com SUM() FILTER, participação percentual por linha.
SELECT categoria,
       SUM(qtd)                                                           AS pecas,
       ROUND(100.0 * SUM(qtd) FILTER (WHERE tamanho = 'P')  / SUM(qtd), 1) AS "P_pct",
       ROUND(100.0 * SUM(qtd) FILTER (WHERE tamanho = 'M')  / SUM(qtd), 1) AS "M_pct",
       ROUND(100.0 * SUM(qtd) FILTER (WHERE tamanho = 'G')  / SUM(qtd), 1) AS "G_pct",
       ROUND(100.0 * SUM(qtd) FILTER (WHERE tamanho = 'GG') / SUM(qtd), 1) AS "GG_pct"
  FROM vw_itens_vendidos
 GROUP BY categoria
 ORDER BY pecas DESC;
