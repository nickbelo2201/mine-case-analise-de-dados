-- Pergunta: quais categorias saem juntas? (vitrine, combos, "compre junto")
-- Técnicas: market basket analysis com self-join — suporte, confiança e lift.
-- lift > 1 → as duas aparecem juntas mais do que o acaso explicaria.
with cesta as (
  select distinct venda_id, categoria from vw_itens_vendidos
),
total as (
  select count(distinct venda_id)::numeric as n from cesta
),
suporte as (
  select categoria, count(*) as vendas from cesta group by categoria
),
pares as (
  select a.categoria as cat_a, b.categoria as cat_b, count(*) as juntas
    from cesta a
    join cesta b on a.venda_id = b.venda_id and a.categoria < b.categoria
   group by 1, 2
)
select cat_a || ' + ' || cat_b                              as par,
       juntas                                               as vendas_juntas,
       round(100.0 * juntas / t.n, 2)                       as suporte_pct,
       round(100.0 * juntas / sa.vendas, 1)                 as confianca_a_para_b_pct,
       round(juntas * t.n / (sa.vendas * sb.vendas), 2)     as lift
  from pares
  join suporte sa on sa.categoria = cat_a
  join suporte sb on sb.categoria = cat_b
 cross join total t
 order by lift desc;
