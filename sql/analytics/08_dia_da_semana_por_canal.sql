-- Pergunta: em que dia a loja e o online vendem? (escala de equipe e horário de campanha)
-- Técnicas: EXTRACT(isodow), pivot por canal com FILTER, média por dia calendário.
WITH por_dia AS (
  SELECT created_at::DATE                          AS dia,
         EXTRACT(ISODOW FROM created_at)::INT      AS dow,
         COUNT(*) FILTER (WHERE canal = 'loja')    AS vendas_loja,
         COUNT(*) FILTER (WHERE canal <> 'loja')   AS vendas_online,
         SUM(total_cents)                          AS receita
    FROM vw_vendas
   GROUP BY 1, 2
)
SELECT (ARRAY['Seg','Ter','Qua','Qui','Sex','Sáb','Dom'])[dow] AS dia_semana,
       COUNT(*)                                    AS dias_com_venda,
       ROUND(AVG(vendas_loja), 1)                  AS media_vendas_loja,
       ROUND(AVG(vendas_online), 1)                AS media_vendas_online,
       ROUND(AVG(receita) / 100.0, 2)              AS receita_media_dia_rs
  FROM por_dia
 GROUP BY dow
 ORDER BY dow;
