-- Pergunta: qual canal dá mais dinheiro de verdade, depois de desconto, custo e taxa?
-- Técnicas: ROLLUP para subtotal, custo congelado no item (snapshot), taxa de maquininha.
-- É a mesma separação que o financeiro do app faz entre "vendi" e "recebo de verdade".
select coalesce(canal, 'TOTAL')                                        as canal,
       count(*)                                                        as vendas,
       round(sum(subtotal_cents) / 100.0, 2)                           as receita_bruta_rs,
       round(sum(discount_cents) / 100.0, 2)                           as descontos_rs,
       round(sum(shipping_cents) / 100.0, 2)                           as frete_rs,
       round(sum(total_cents) / 100.0, 2)                              as receita_liquida_rs,
       round(sum(cost_cents) / 100.0, 2)                               as cmv_rs,
       round(sum(fee_cents) / 100.0, 2)                                as taxas_rs,
       round((sum(total_cents) - sum(cost_cents) - sum(fee_cents)) / 100.0, 2) as margem_contrib_rs,
       round(100.0 * (sum(total_cents) - sum(cost_cents) - sum(fee_cents)) / sum(total_cents), 1)
                                                                       as margem_pct
  from vw_vendas
 group by rollup (canal)
 order by grouping(canal), receita_liquida_rs desc;
