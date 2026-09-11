-- Pergunta: dá para confiar nesses números?
-- Checagens que rodam antes de qualquer análise. Resultado esperado: tudo zero.
-- A primeira usa a função de produção check_stock_integrity() (011_stock.sql):
-- como o saldo é um ledger, a soma dos movimentos TEM que bater com o saldo.
SELECT 'Saldo de estoque diverge da soma dos movimentos' AS verificacao,
       COUNT(*) AS ocorrencias
  FROM check_stock_integrity()
UNION ALL
SELECT 'Pedido com total ≠ itens − desconto + frete',
       COUNT(*)
  FROM orders o
 WHERE o.total_cents <> (SELECT COALESCE(SUM(i.unit_price_cents * i.quantity), 0)
                           FROM order_items i WHERE i.order_id = o.id)
                        - o.discount_cents + o.shipping_cents
UNION ALL
SELECT 'Venda de balcão com pagamentos ≠ total',
       COUNT(*)
  FROM pos_sales s
 WHERE s.status = 'concluida'
   AND s.total_cents <> (SELECT COALESCE(SUM(p.amount_cents), 0)
                           FROM pos_payments p WHERE p.sale_id = s.id)
UNION ALL
SELECT 'Cliente com WhatsApp fora do padrão E.164 (55 + DDD + número)',
       COUNT(*)
  FROM customers
 WHERE whatsapp !~ '^55[0-9]{10,11}$'
UNION ALL
SELECT 'Item de pedido sem variante (estoque não rastreável)',
       COUNT(*)
  FROM order_items
 WHERE variant_id IS NULL
UNION ALL
SELECT 'Reserva maior que o saldo físico',
       COUNT(*)
  FROM product_variants
 WHERE stock_reserved > stock_on_hand
UNION ALL
SELECT 'Cliente criado depois da própria primeira compra',
       COUNT(*)
  FROM customers c
  JOIN (SELECT customer_id, MIN(created_at) AS primeira FROM vw_vendas
         WHERE customer_id IS NOT NULL GROUP BY 1) f ON f.customer_id = c.id
 WHERE c.created_at > f.primeira;
