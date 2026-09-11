-- Pergunta: quem são as melhores clientes, e quem está sumindo?
-- Técnicas: RFM com NTILE, data de corte = última venda da base (não now(),
-- para o resultado ser reprodutível), CASE para regras de segmento,
-- janela sobre agregado para % da receita.
-- Só funciona porque o cliente é único por WhatsApp normalizado (ver 013_customers.sql):
-- sem isso, a mesma pessoa viraria 3 clientes e a frequência seria subestimada.
with base as (
  select customer_id,
         max(created_at)  as ultima_compra,
         count(*)         as frequencia,
         sum(total_cents) as valor
    from vw_vendas
   where customer_id is not null
   group by customer_id
),
corte as (
  select max(created_at) as data_corte from vw_vendas
),
score as (
  select b.*,
         extract(day from c.data_corte - b.ultima_compra)::int as recencia_dias,
         ntile(5) over (order by b.ultima_compra)              as r,
         ntile(5) over (order by b.frequencia, b.valor)        as f,
         ntile(5) over (order by b.valor)                      as m
    from base b cross join corte c
),
segmento as (
  select *,
         case
           when r >= 4 and f >= 4 then '1. Campeãs'
           when r >= 3 and f >= 3 then '2. Leais'
           when r >= 4 and f <= 2 then '3. Novas / promissoras'
           when r <= 2 and f >= 4 then '4. Em risco (eram boas)'
           when r <= 2 and f <= 2 then '6. Hibernando'
           else                        '5. Precisam de atenção'
         end as segmento
    from score
)
select segmento,
       count(*)                                                   as clientes,
       round(avg(recencia_dias))                                  as recencia_media_dias,
       round(avg(frequencia), 1)                                  as compras_media,
       round(avg(valor) / 100.0, 2)                               as valor_medio_rs,
       round(sum(valor) / 100.0, 2)                               as receita_rs,
       round(100.0 * sum(valor) / sum(sum(valor)) over (), 1)     as pct_receita
  from segmento
 group by segmento
 order by segmento;
