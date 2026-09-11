-- Pergunta: o online está perdendo pedidos? Quanto tempo a cliente espera pela peça?
-- Técnicas: pivot de eventos (order_events) com MIN() FILTER, mediana com
-- percentile_cont — média de prazo esconde os atrasos longos.
with eventos as (
  select order_id,
         min(created_at) filter (where to_status = 'aguardando') as criado_em,
         min(created_at) filter (where to_status = 'entregue')   as entregue_em
    from order_events
   group by order_id
)
select to_char(date_trunc('month', o.created_at), 'YYYY-MM')                      as mes,
       count(*)                                                                   as pedidos,
       round(100.0 * count(*) filter (where o.status = 'cancelado') / count(*), 1) as cancelado_pct,
       round(100.0 * count(*) filter (where o.status = 'devolvido') / count(*), 1) as devolvido_pct,
       round((percentile_cont(0.5) within group (
                order by extract(epoch from e.entregue_em - e.criado_em) / 86400))::numeric, 1)
                                                                                  as lead_time_mediano_dias,
       round((percentile_cont(0.9) within group (
                order by extract(epoch from e.entregue_em - e.criado_em) / 86400))::numeric, 1)
                                                                                  as lead_time_p90_dias
  from orders o
  left join eventos e on e.order_id = o.id
 where o.channel in ('site', 'whatsapp')
 group by 1
 order by 1;
