-- Pergunta: quais produtos sustentam a loja? (Pareto / curva ABC)
-- Técnicas: soma acumulada com window frame explícito, classificação por faixa.
-- Receita no grão de item = preço unitário congelado × quantidade (antes do desconto do pedido).
with produto as (
  select produto, categoria,
         sum(qtd)           as pecas,
         sum(receita_cents) as receita,
         sum(receita_cents - custo_cents) as margem
    from vw_itens_vendidos
   group by produto, categoria
),
acumulado as (
  select *,
         100.0 * sum(receita) over (order by receita desc rows between unbounded preceding and current row)
               / sum(receita) over () as pct_acumulado,
         row_number() over (order by receita desc) as posicao
    from produto
)
select posicao,
       produto,
       categoria,
       pecas,
       round(receita / 100.0, 2)            as receita_rs,
       round(100.0 * margem / receita, 1)   as margem_pct,
       round(pct_acumulado, 1)              as pct_acumulado,
       case when pct_acumulado <= 80 then 'A'
            when pct_acumulado <= 95 then 'B'
            else 'C' end                    as classe
  from acumulado
 order by posicao;
