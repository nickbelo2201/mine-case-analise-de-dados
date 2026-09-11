-- Pergunta: na hora de comprar do fornecedor, qual a proporção de cada tamanho por categoria?
-- Técnicas: pivot com SUM() FILTER, participação percentual por linha.
select categoria,
       sum(qtd)                                                           as pecas,
       round(100.0 * sum(qtd) filter (where tamanho = 'P')  / sum(qtd), 1) as "P_pct",
       round(100.0 * sum(qtd) filter (where tamanho = 'M')  / sum(qtd), 1) as "M_pct",
       round(100.0 * sum(qtd) filter (where tamanho = 'G')  / sum(qtd), 1) as "G_pct",
       round(100.0 * sum(qtd) filter (where tamanho = 'GG') / sum(qtd), 1) as "GG_pct"
  from vw_itens_vendidos
 group by categoria
 order by pecas desc;
