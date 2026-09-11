-- Pergunta: como a receita evolui mês a mês, e quanto dela já vem do online?
-- Técnicas: CTE, agregação condicional (FILTER), window functions (LAG, média móvel).
-- Observação: date_trunc em timestamptz respeita o fuso da sessão (America/Sao_Paulo);
-- sem isso, uma venda às 22h do dia 31 cairia no mês seguinte.
with mensal as (
  select date_trunc('month', created_at)::date                     as mes,
         sum(total_cents)                                         as total,
         sum(total_cents) filter (where canal = 'loja')           as loja,
         sum(total_cents) filter (where canal in ('site', 'whatsapp')) as online,
         count(*)                                                 as vendas
    from vw_vendas
   group by 1
)
select to_char(mes, 'YYYY-MM')                                          as mes,
       round(total / 100.0, 2)                                          as receita_rs,
       vendas,
       round(total / 100.0 / vendas, 2)                                 as ticket_medio_rs,
       round(100.0 * online / total, 1)                                 as pct_online,
       round(100.0 * (total - lag(total) over w) / lag(total) over w, 1) as var_mom_pct,
       round(avg(total) over (order by mes rows between 2 preceding and current row) / 100.0, 2)
                                                                        as media_movel_3m_rs
  from mensal
window w as (order by mes)
 order by mes;
