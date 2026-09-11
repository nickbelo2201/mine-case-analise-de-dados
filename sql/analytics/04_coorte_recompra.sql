-- Pergunta: das clientes que compraram pela primeira vez em cada mês,
-- quantas voltaram 1, 2, 3 e 6 meses depois?
-- Técnicas: coorte por mês de primeira compra, diferença de meses em aritmética
-- inteira, pivot com COUNT(DISTINCT) FILTER. Célula que ainda não aconteceu
-- (coorte recente demais para ter "mês 6") sai como NULL, não como 0%.
with compras as (
  select customer_id, date_trunc('month', created_at)::date as mes
    from vw_vendas
   where customer_id is not null
   group by 1, 2
),
primeira as (
  select customer_id, min(mes) as coorte from compras group by 1
),
atividade as (
  select p.coorte,
         c.customer_id,
         (extract(year from c.mes) * 12 + extract(month from c.mes))
       - (extract(year from p.coorte) * 12 + extract(month from p.coorte)) as m
    from compras c join primeira p using (customer_id)
),
ultimo as (
  select max(mes) as mes from compras
),
pivot as (
  select a.coorte,
         (extract(year from u.mes) * 12 + extract(month from u.mes))
       - (extract(year from a.coorte) * 12 + extract(month from a.coorte)) as meses_observados,
         count(distinct customer_id) filter (where m = 0)  as n0,
         count(distinct customer_id) filter (where m = 1)  as n1,
         count(distinct customer_id) filter (where m = 2)  as n2,
         count(distinct customer_id) filter (where m = 3)  as n3,
         count(distinct customer_id) filter (where m = 6)  as n6,
         count(distinct customer_id) filter (where m >= 1) as n_voltou
    from atividade a cross join ultimo u
   group by a.coorte, u.mes
)
select to_char(coorte, 'YYYY-MM')                                          as coorte,
       n0                                                                  as clientes_novas,
       case when meses_observados >= 1 then round(100.0 * n1 / n0, 1) end  as m1_pct,
       case when meses_observados >= 2 then round(100.0 * n2 / n0, 1) end  as m2_pct,
       case when meses_observados >= 3 then round(100.0 * n3 / n0, 1) end  as m3_pct,
       case when meses_observados >= 6 then round(100.0 * n6 / n0, 1) end  as m6_pct,
       round(100.0 * n_voltou / n0, 1)                                     as voltou_ate_hoje_pct
  from pivot
 order by coorte;
