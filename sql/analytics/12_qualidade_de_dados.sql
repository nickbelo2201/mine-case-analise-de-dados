-- Pergunta: dá para confiar nesses números?
-- Checagens que rodam antes de qualquer análise. Resultado esperado: tudo zero.
-- A primeira usa a função de produção check_stock_integrity() (011_stock.sql):
-- como o saldo é um ledger, a soma dos movimentos TEM que bater com o saldo.
select 'Saldo de estoque diverge da soma dos movimentos' as verificacao,
       count(*) as ocorrencias
  from check_stock_integrity()
union all
select 'Pedido com total ≠ itens − desconto + frete',
       count(*)
  from orders o
 where o.total_cents <> (select coalesce(sum(i.unit_price_cents * i.quantity), 0)
                           from order_items i where i.order_id = o.id)
                        - o.discount_cents + o.shipping_cents
union all
select 'Venda de balcão com pagamentos ≠ total',
       count(*)
  from pos_sales s
 where s.status = 'concluida'
   and s.total_cents <> (select coalesce(sum(p.amount_cents), 0)
                           from pos_payments p where p.sale_id = s.id)
union all
select 'Cliente com WhatsApp fora do padrão E.164 (55 + DDD + número)',
       count(*)
  from customers
 where whatsapp !~ '^55[0-9]{10,11}$'
union all
select 'Item de pedido sem variante (estoque não rastreável)',
       count(*)
  from order_items
 where variant_id is null
union all
select 'Reserva maior que o saldo físico',
       count(*)
  from product_variants
 where stock_reserved > stock_on_hand
union all
select 'Cliente criado depois da própria primeira compra',
       count(*)
  from customers c
  join (select customer_id, min(created_at) as primeira from vw_vendas
         where customer_id is not null group by 1) f on f.customer_id = c.id
 where c.created_at > f.primeira;
