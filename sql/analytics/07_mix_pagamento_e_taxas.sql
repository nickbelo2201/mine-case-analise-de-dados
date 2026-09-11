-- Pergunta: quanto a maquininha come do faturamento do balcão?
-- Técnicas: join com filtro de status, participação com window sobre agregado.
-- Pagamento dividido (PIX + cartão) é uma linha por forma em pos_payments,
-- por isso "transações" ≠ "vendas".
select p.method                                                        as forma,
       count(*)                                                        as transacoes,
       round(sum(p.amount_cents) / 100.0, 2)                           as valor_rs,
       round(100.0 * sum(p.amount_cents) / sum(sum(p.amount_cents)) over (), 1) as pct_valor,
       round(avg(p.installments) filter (where p.method = 'credito_parcelado'), 1) as parcelas_media,
       round(sum(p.fee_cents) / 100.0, 2)                              as taxas_rs,
       round(100.0 * sum(p.fee_cents) / sum(p.amount_cents), 2)        as taxa_efetiva_pct
  from pos_payments p
  join pos_sales s on s.id = p.sale_id
 where s.status = 'concluida'
 group by p.method
 order by valor_rs desc;
