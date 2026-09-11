-- Pergunta: em que dia a loja e o online vendem? (escala de equipe e horário de campanha)
-- Técnicas: EXTRACT(isodow), pivot por canal com FILTER, média por dia calendário.
with por_dia as (
  select created_at::date                          as dia,
         extract(isodow from created_at)::int      as dow,
         count(*) filter (where canal = 'loja')    as vendas_loja,
         count(*) filter (where canal <> 'loja')   as vendas_online,
         sum(total_cents)                          as receita
    from vw_vendas
   group by 1, 2
)
select (array['Seg','Ter','Qua','Qui','Sex','Sáb','Dom'])[dow] as dia_semana,
       count(*)                                    as dias_com_venda,
       round(avg(vendas_loja), 1)                  as media_vendas_loja,
       round(avg(vendas_online), 1)                as media_vendas_online,
       round(avg(receita) / 100.0, 2)              as receita_media_dia_rs
  from por_dia
 group by dow
 order by dow;
