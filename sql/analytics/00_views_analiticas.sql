-- ============================================================
-- Camada analítica: uma venda é uma venda, venha de onde vier.
--
-- O modelo transacional tem dois fluxos com tabelas próprias:
--   orders / order_items        → site e WhatsApp (ciclo de status longo)
--   pos_sales / pos_sale_items  → balcão (venda nasce concluída, tem caixa e taxa)
-- Isso é o certo para operar, mas péssimo para analisar. Estas views
-- unificam os dois num grão único, com as mesmas regras de negócio
-- que o painel do admin usa (ver app-excerpts/supabase-dashboard.ts).
-- ============================================================

-- Regra de "vendido": pedido online conta a partir de confirmado;
-- devolvido e cancelado não entram na receita.
create or replace view vw_vendas as
select o.id                     as venda_id,
       o.channel                as canal,
       o.customer_id,
       o.created_at,
       o.subtotal_cents,
       o.discount_cents,
       o.shipping_cents,
       o.total_cents,
       coalesce(i.custo, 0)     as cost_cents,
       0                        as fee_cents
  from orders o
  left join (select order_id, sum(cost_cents_snapshot * quantity)::int as custo
               from order_items group by order_id) i on i.order_id = o.id
 where o.status in ('confirmado', 'pago', 'enviado', 'entregue')
union all
select s.id,
       'loja',
       s.customer_id,
       s.created_at,
       s.subtotal_cents,
       s.discount_cents,
       0,
       s.total_cents,
       s.cost_cents,
       coalesce(p.taxa, 0)
  from pos_sales s
  left join (select sale_id, sum(fee_cents)::int as taxa
               from pos_payments group by sale_id) p on p.sale_id = s.id
 where s.status = 'concluida';

-- Grão de item, já com categoria e produto do catálogo atual.
-- Nome/tamanho/cor vêm do snapshot congelado na venda.
create or replace view vw_itens_vendidos as
select v.venda_id,
       v.canal,
       v.customer_id,
       v.created_at,
       i.variant_id,
       pv.product_id,
       i.product_name_snapshot                   as produto,
       p.category                                as categoria,
       i.size_snapshot                           as tamanho,
       i.color_snapshot                          as cor,
       i.quantity                                as qtd,
       i.unit_price_cents * i.quantity           as receita_cents,
       i.cost_cents_snapshot * i.quantity        as custo_cents
  from vw_vendas v
  join (
    select order_id as venda_id, variant_id, product_name_snapshot, size_snapshot, color_snapshot,
           quantity, unit_price_cents, cost_cents_snapshot
      from order_items
    union all
    select sale_id, variant_id, product_name_snapshot, size_snapshot, color_snapshot,
           quantity, unit_price_cents, cost_cents_snapshot
      from pos_sale_items
  ) i on i.venda_id = v.venda_id
  join product_variants pv on pv.id = i.variant_id
  join products p          on p.id  = pv.product_id;

-- Views analíticas também não são públicas.
revoke all on vw_vendas, vw_itens_vendidos from anon, authenticated;
