-- Pergunta: onde tem dinheiro parado no estoque e onde vai faltar peça?
-- Técnicas: venda média diária dos últimos 90 dias a partir do ledger de estoque
-- (stock_movements), cobertura em dias, capital imobilizado a custo, NULLIF contra divisão por zero.
with corte as (
  select max(created_at) as data_corte from stock_movements
),
saidas_90d as (
  select m.variant_id, -sum(m.delta) as vendidas
    from stock_movements m cross join corte c
   where m.reason in ('venda_online', 'venda_loja')
     and m.created_at > c.data_corte - interval '90 days'
   group by m.variant_id
),
detalhe as (
  select v.id,
         v.stock_on_hand                                                   as estoque,
         coalesce(s.vendidas, 0)                                           as vendidas_90d,
         v.stock_on_hand * v.cost_cents                                    as capital_cents,
         v.stock_on_hand / nullif(coalesce(s.vendidas, 0) / 90.0, 0)       as cobertura_dias
    from product_variants v
    left join saidas_90d s on s.variant_id = v.id
   where v.active
),
situacao as (
  select *,
         case
           when estoque = 0 and vendidas_90d > 0 then '1. Ruptura (vende e acabou)'
           when cobertura_dias < 15              then '2. Repor em até 15 dias'
           when vendidas_90d = 0 and estoque > 0 then '5. Parado (0 vendas em 90 dias)'
           when cobertura_dias > 120             then '4. Excesso (> 120 dias)'
           else                                       '3. Saudável'
         end as situacao
    from detalhe
)
select situacao,
       count(*)                              as variantes,
       sum(estoque)                          as pecas,
       round(sum(capital_cents) / 100.0, 2)  as capital_a_custo_rs,
       round(100.0 * sum(capital_cents) / sum(sum(capital_cents)) over (), 1) as pct_capital,
       round(avg(cobertura_dias))            as cobertura_media_dias
  from situacao
 group by situacao
 order by situacao;
