-- ============================================================
-- Seed sintético — 12 meses de operação (set/2025 a ago/2026).
--
-- NENHUM dado aqui é real. Os dados do cliente não saem do banco
-- de produção; este script gera uma base com o mesmo formato e
-- com comportamentos plausíveis de varejo de moda:
--   • sazonalidade (Black Friday, Natal, Dia das Mães) + tendência de alta;
--   • loja física fechada aos domingos, venda online a qualquer hora;
--   • clientes recorrentes com distribuição concentrada (poucos compram muito);
--   • produtos com popularidade desigual (base para a curva ABC);
--   • cancelamentos, devoluções e pedidos ainda em andamento no fim do período.
--
-- Tudo é set-based (generate_series + CTEs), sem loop, e reprodutível
-- via setseed. O estoque é lançado como movimentos em stock_movements,
-- de modo que check_stock_integrity() fecha em zero.
-- ============================================================

select setseed(0.42);

-- ------------------------------------------------------------
-- 1. Catálogo: 5 categorias × modelos × 2 linhas (Essencial/Premium)
-- ------------------------------------------------------------
create temp table t_cat (cat text, modelos text[], preco_min int, preco_max int);
insert into t_cat values
  ('camisetas', array['Camiseta Básica','Camiseta Oversized','Camiseta Estampada','Camiseta Gola V','Regata'], 5990, 11990),
  ('calcas',    array['Calça Jeans Reta','Calça Cargo','Calça Alfaiataria','Calça Jogger'],               12990, 24990),
  ('bermudas',  array['Bermuda Jeans','Bermuda Sarja','Bermuda Moletom'],                                 7990, 14990),
  ('moletons',  array['Moletom Canguru','Moletom Careca','Blusão Fleece'],                               14990, 25990),
  ('jaquetas',  array['Jaqueta Jeans','Jaqueta Corta-vento','Jaqueta Couro Eco','Bomber'],               19990, 36990);

insert into products (name, model, category, price, price_cents, status, slug, description, created_at)
select nome,
       modelo,
       cat,
       'R$ ' || replace(to_char(preco / 100.0, 'FM9990.00'), '.', ','),   -- formato legado (texto)
       preco,
       'ativo',
       slugify(nome),
       'Produto sintético para o case.',
       timestamptz '2025-08-01' + random() * interval '20 days'
  from (
    select c.cat,
           m.modelo_nome || ' ' || l.linha                         as nome,
           'MN-' || lpad((row_number() over (order by c.cat, m.ord, l.linha))::text, 3, '0') as modelo,
           (round(((c.preco_min + random() * (c.preco_max - c.preco_min)) * l.mult) / 1000) * 1000 - 10)::int as preco
      from t_cat c
      cross join lateral unnest(c.modelos) with ordinality m(modelo_nome, ord)
      cross join (values ('Essencial', 1.0), ('Premium', 1.45)) l(linha, mult)
  ) x;

-- Variantes: 2 cores por produto × grade P/M/G/GG. Custo congelado ~38-47% do preço.
insert into product_variants (product_id, color, size, sku, cost_cents, low_stock_threshold)
select p.id,
       cor,
       tam,
       upper(p.model || '-' || slugify(cor) || '-' || tam),
       round(p.price_cents * (0.38 + (abs(hashtext(p.model)) % 10) / 100.0))::int,
       2
  from products p
  cross join lateral (
    select cor
      from unnest(array['Preto','Branco','Off-white','Azul Marinho','Verde Oliva','Caramelo']) cor
     where p.id is not null                      -- força reavaliação por produto
     order by random()
     limit 2
  ) cores
  cross join unnest(array['P','M','G','GG']) tam;

-- ------------------------------------------------------------
-- 2. Clientes: 700 pessoas fictícias com WhatsApp normalizado
-- ------------------------------------------------------------
create temp table t_cli as
select g as n,
       gen_random_uuid() as id,
       (array['Ana','Beatriz','Camila','Daniela','Eduarda','Fernanda','Gabriela','Helena','Isabela','Julia',
              'Lucas','Mateus','Pedro','Rafael','Thiago','Bruno','Gustavo','Felipe','Larissa','Mariana'])[1 + floor(random() * 20)::int]
         || ' ' ||
       (array['Silva','Souza','Oliveira','Santos','Lima','Pereira','Costa','Almeida','Ferreira','Rocha'])[1 + floor(random() * 10)::int] as nome,
       -- Número determinístico e único por cliente, escrito "sujo" de propósito:
       -- normalize_phone é quem padroniza para E.164.
       format('(%s) 9%s-%s',
              (array['11','11','11','21','31','41','19'])[1 + (g % 7)],
              substr(lpad(((g * 7919) % 100000000)::text, 8, '0'), 1, 4),
              substr(lpad(((g * 7919) % 100000000)::text, 8, '0'), 5, 4)) as whatsapp_bruto,
       (array['site','loja','whatsapp','loja'])[1 + floor(random() * 4)::int] as origem
  from generate_series(1, 2500) g;

insert into customers (id, name, whatsapp, source, accepts_marketing, created_at)
select id, nome, normalize_phone(whatsapp_bruto), origem, random() < 0.6,
       timestamptz '2025-08-01' + random() * interval '390 days'
  from t_cli;

-- ------------------------------------------------------------
-- 3. Eventos de venda com sazonalidade e tendência
-- ------------------------------------------------------------
create temp table t_venda as
with cand as (
  select timestamptz '2025-09-01 00:00:00-03' + random() * interval '365 days' as ts,
         random() as r_keep, random() as r_canal, random() as r_cli,
         random() as r_status, random() as r_desc, random() as r_hora
    from generate_series(1, 11000)
),
filtrado as (
  select *,
         -- peso do mês × tendência de crescimento ao longo do ano
         (case extract(month from ts at time zone 'America/Sao_Paulo')
            when 12 then 1.00 when 11 then 0.85 when 5 then 0.78
            when 1 then 0.42 when 2 then 0.45 when 3 then 0.50
            else 0.58 end)
         * (0.70 + 0.60 * extract(epoch from ts - timestamptz '2025-09-01 00:00:00-03') / (365 * 86400)) as peso
    from cand
),
canal as (
  select *,
         case when r_canal < 0.42 then 'loja' when r_canal < 0.86 then 'site' else 'whatsapp' end as canal0
    from filtrado
   where r_keep < peso
)
select row_number() over (order by ts) as n,
       gen_random_uuid() as id,
       -- loja: fecha domingo, horário comercial 9h-20h
       case when canal0 = 'loja' and extract(isodow from ts at time zone 'America/Sao_Paulo') = 7 then 'site'
            else canal0 end as canal,
       case when canal0 = 'loja' and extract(isodow from ts at time zone 'America/Sao_Paulo') <> 7
            then (date_trunc('day', ts at time zone 'America/Sao_Paulo') + interval '9 hours' + r_hora * interval '11 hours')
                   at time zone 'America/Sao_Paulo'
            else ts end as ts,
       -- 20% das vendas de loja e 5% das online sem cliente identificado.
       -- Das identificadas: 40% vêm de um núcleo fiel (~400 clientes, concentrado),
       -- 60% da base ampla (2.500 clientes, a maioria compra 1 ou 2 vezes).
       case when (canal0 = 'loja' and r_cli < 0.20) or (canal0 <> 'loja' and r_cli < 0.05) then null
            when random() < 0.40 then 1 + floor(power(random(), 1.5) * 400)::int
            else 1 + floor(random() * 2500)::int end as cli_n,
       r_status, r_desc
  from canal;

-- ------------------------------------------------------------
-- 4. Itens: popularidade desigual de produto, grade com M/G mais vendidos
-- ------------------------------------------------------------
create temp table t_prod as
select id, row_number() over (order by random()) as rk from products;

create temp table t_var as
select v.id, v.product_id, v.size, v.cost_cents, p.price_cents, p.name,
       dense_rank() over (partition by v.product_id order by v.color) as cor_n, v.color
  from product_variants v join products p on p.id = v.product_id;

create temp table t_linha as
select v.n, v.id as venda_id, k,
       1 + floor(power(random(), 1.9) * (select count(*) from products))::int as prod_rk,
       case when random() < 0.20 then 'P' when random() < 0.45 then 'M'
            when random() < 0.60 then 'G' else 'GG' end as tam,
       1 + (random() < 0.5)::int as cor_n,
       case when random() < 0.9 then 1 else 2 end as qty
  from t_venda v
  cross join lateral generate_series(1, 1 + (random() < 0.35 and v.n > 0)::int + (random() < 0.10)::int) k;

-- Afinidade de cesta: metade dos 2º itens vem da categoria "par" do 1º
-- (calça → camiseta, camiseta → bermuda, jaqueta → moletom...).
update t_linha l2
   set prod_rk = (
     select tp.rk
       from t_prod tp join products p on p.id = tp.id
      where p.category = (
              select case p1.category
                       when 'calcas'    then 'camisetas'
                       when 'camisetas' then 'bermudas'
                       when 'bermudas'  then 'camisetas'
                       when 'jaquetas'  then 'moletons'
                       else 'calcas' end
                from t_linha l1
                join t_prod t1   on t1.rk = l1.prod_rk
                join products p1 on p1.id = t1.id
               where l1.venda_id = l2.venda_id and l1.k = 1)
      order by random() + l2.k * 0
      limit 1)
 where l2.k = 2 and random() < 0.5;

-- Peças de frio (moletom, jaqueta) puxam para G/GG.
update t_linha l
   set tam = case when random() < 0.10 then 'P' when random() < 0.35 then 'M'
                  when random() < 0.65 then 'G' else 'GG' end
  from t_prod tp join products p on p.id = tp.id
 where tp.rk = l.prod_rk and p.category in ('moletons', 'jaquetas');

create temp table t_item as
select l.venda_id, tv.id as variant_id, tv.product_id, tv.name, tv.size, tv.color,
       l.qty, tv.price_cents as unit_price_cents, tv.cost_cents
  from t_linha l
  join t_prod tp on tp.rk = l.prod_rk
  join t_var  tv on tv.product_id = tp.id and tv.size = l.tam and tv.cor_n = l.cor_n;

-- Totais por venda (10% de desconto em ~15% das vendas; frete grátis acima de R$ 299)
create temp table t_total as
select v.*,
       s.subtotal,
       case when v.r_desc < 0.15 then round(s.subtotal * 0.10)::int else 0 end as desconto,
       case when v.canal <> 'loja' and s.subtotal < 29900 then 1990 else 0 end as frete,
       s.custo
  from t_venda v
  join (select venda_id,
               sum(unit_price_cents * qty)::int as subtotal,
               sum(cost_cents * qty)::int       as custo
          from t_item group by venda_id) s on s.venda_id = v.id;

-- ------------------------------------------------------------
-- 5. Pedidos online (site + WhatsApp)
-- ------------------------------------------------------------
insert into orders (id, channel, customer_id, status, subtotal_cents, discount_cents, shipping_cents,
                    total_cents, payment_method, payment_status, customer_name, customer_phone,
                    created_at, updated_at, confirmed_at, cancelled_at, reserved_until)
select t.id, t.canal, c.id,
       st.status,
       t.subtotal, t.desconto, t.frete, t.subtotal - t.desconto + t.frete,
       case when t.r_desc < 0.55 then 'pix' else 'cartao' end,
       case st.status when 'aguardando' then 'pendente' when 'cancelado' then 'pendente'
                      when 'devolvido' then 'estornado' else 'pago' end,
       c.nome, normalize_phone(c.whatsapp_bruto),
       t.ts, t.ts,
       case when st.status not in ('aguardando', 'cancelado') then t.ts + interval '2 hours' end,
       case when st.status = 'cancelado' then t.ts + interval '2 days' end,
       t.ts + interval '48 hours'
  from t_total t
  left join t_cli c on c.n = t.cli_n
  cross join lateral (
    select case
             when t.ts > timestamptz '2026-08-25' then
               (array['aguardando','pago','enviado'])[1 + floor(t.r_status * 3)::int]
             when t.r_status < 0.07 then 'cancelado'
             when t.r_status < 0.10 then 'devolvido'
             else 'entregue'
           end as status
  ) st
 where t.canal <> 'loja';

insert into order_items (order_id, product_id, variant_id, size, quantity, unit_price, unit_price_cents,
                         cost_cents_snapshot, product_name_snapshot, size_snapshot, color_snapshot, created_at)
select i.venda_id, i.product_id, i.variant_id, i.size, i.qty, i.unit_price_cents / 100.0, i.unit_price_cents,
       i.cost_cents, i.name, i.size, i.color, o.created_at
  from t_item i join orders o on o.id = i.venda_id;

-- Histórico de status (order_events): base do lead time de entrega
insert into order_events (order_id, from_status, to_status, created_at, created_by)
select o.id, e.de, e.para, o.created_at + e.depois, 'seed'
  from orders o
  cross join lateral (
    select null::text as de, 'aguardando' as para, interval '0' as depois
    union all select 'aguardando', 'confirmado', interval '2 hours'
     where o.status not in ('aguardando', 'cancelado')
    union all select 'aguardando', 'cancelado', interval '2 days'
     where o.status = 'cancelado'
    union all select 'confirmado', 'enviado', interval '1 day' + (abs(hashtext(o.id::text)) % 48) * interval '1 hour'
     where o.status in ('enviado', 'entregue', 'devolvido')
    union all select 'enviado', 'entregue', interval '4 days' + (abs(hashtext(o.id::text)) % 120) * interval '1 hour'
     where o.status in ('entregue', 'devolvido')
    union all select 'entregue', 'devolvido', interval '12 days'
     where o.status = 'devolvido'
  ) e;

-- ------------------------------------------------------------
-- 6. PDV: sessões de caixa por dia, vendas, itens e pagamentos
-- ------------------------------------------------------------
insert into cash_sessions (id, opened_by, opened_at, opening_cents, closed_by, closed_at)
select gen_random_uuid(), 'Vendedora A', dia + interval '8 hours 45 minutes', 20000,
       'Vendedora A', dia + interval '20 hours 15 minutes'
  from (select distinct date_trunc('day', ts at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo' as dia
          from t_total where canal = 'loja') d;

insert into pos_sales (id, session_id, customer_id, seller, subtotal_cents, discount_cents, total_cents,
                       cost_cents, status, cancelled_at, cancelled_by, cancel_reason, created_at)
select t.id, cs.id, c.id,
       (array['Vendedora A','Vendedora B','Vendedora C'])[1 + (t.n % 3)::int],
       t.subtotal, t.desconto, t.subtotal - t.desconto, t.custo,
       case when t.r_status < 0.02 then 'cancelada' else 'concluida' end,
       case when t.r_status < 0.02 then t.ts + interval '10 minutes' end,
       case when t.r_status < 0.02 then 'Vendedora A' end,
       case when t.r_status < 0.02 then 'Cliente desistiu no caixa' end,
       t.ts
  from t_total t
  left join t_cli c on c.n = t.cli_n
  join cash_sessions cs
    on date_trunc('day', cs.opened_at at time zone 'America/Sao_Paulo')
     = date_trunc('day', t.ts at time zone 'America/Sao_Paulo')
 where t.canal = 'loja';

insert into pos_sale_items (sale_id, variant_id, quantity, unit_price_cents, cost_cents_snapshot,
                            product_name_snapshot, size_snapshot, color_snapshot)
select i.venda_id, i.variant_id, i.qty, i.unit_price_cents, i.cost_cents, i.name, i.size, i.color
  from t_item i join pos_sales s on s.id = i.venda_id;

-- Um pagamento por venda; ~12% dividem em dois (metade PIX + restante cartão).
-- Taxa da maquininha: débito 1,5% · crédito 3,2% · parcelado 4,9% · PIX/dinheiro 0.
with base as (
  select s.id, s.total_cents, random() as r_div, random() as r_met, random() as r_parc
    from pos_sales s where s.total_cents > 0
),
partes as (
  select id, case when r_div < 0.12 then 'pix'
                  when r_met < 0.30 then 'pix'
                  when r_met < 0.45 then 'debito'
                  when r_met < 0.70 then 'credito'
                  when r_met < 0.90 then 'credito_parcelado'
                  else 'dinheiro' end as metodo,
         case when r_div < 0.12 then total_cents / 2 else total_cents end as valor,
         r_parc
    from base
  union all
  select id, 'credito', total_cents - total_cents / 2, r_parc
    from base where r_div < 0.12
)
insert into pos_payments (sale_id, method, amount_cents, installments, fee_cents, brand)
select id, metodo, valor,
       case when metodo = 'credito_parcelado' then 2 + floor(r_parc * 5)::int else 1 end,
       round(valor * case metodo when 'debito' then 0.015 when 'credito' then 0.032
                                 when 'credito_parcelado' then 0.049 else 0 end)::int,
       case when metodo in ('debito','credito','credito_parcelado')
            then (array['Visa','Mastercard','Elo'])[1 + floor(r_parc * 3)::int] end
  from partes;

-- ------------------------------------------------------------
-- 7. Estoque: saídas por venda + entrada inicial que cobre tudo
--    (movimentos gravados com a data real da venda → base do giro)
-- ------------------------------------------------------------
insert into stock_movements (variant_id, delta, reason, ref_type, ref_id, created_by, created_at)
select i.variant_id, -sum(i.quantity)::int, 'venda_online', 'order', o.id, 'seed', o.confirmed_at
  from orders o join order_items i on i.order_id = o.id
 where o.status in ('confirmado','pago','enviado','entregue','devolvido')
 group by i.variant_id, o.id, o.confirmed_at
union all
select i.variant_id, sum(i.quantity)::int, 'devolucao', 'order', o.id, 'seed', o.created_at + interval '12 days'
  from orders o join order_items i on i.order_id = o.id
 where o.status = 'devolvido'
 group by i.variant_id, o.id, o.created_at
union all
select i.variant_id, -sum(i.quantity)::int, 'venda_loja', 'pos_sale', s.id, 'seed', s.created_at
  from pos_sales s join pos_sale_items i on i.sale_id = s.id
 where s.status = 'concluida'
 group by i.variant_id, s.id, s.created_at;

-- Entrada de compra que cobre as vendas + sobra aleatória (0 a 8 peças).
-- Algumas variantes terminam zeradas (ruptura), outras encalhadas.
insert into stock_movements (variant_id, delta, reason, ref_type, note, created_by, created_at)
select v.id,
       coalesce(-m.saidas, 0) + floor(random() * 9)::int + (case when m.saidas is null then 3 else 0 end),
       'entrada_compra', 'purchase', 'Estoque inicial sintético', 'seed', timestamptz '2025-08-25'
  from product_variants v
  left join (select variant_id, sum(delta) as saidas from stock_movements group by variant_id) m
    on m.variant_id = v.id
 where coalesce(-m.saidas, 0) + floor(random() * 9)::int + (case when m.saidas is null then 3 else 0 end) > 0;

-- Saldo materializado = soma dos movimentos
update product_variants v
   set stock_on_hand = m.total
  from (select variant_id, sum(delta)::int as total from stock_movements group by variant_id) m
 where m.variant_id = v.id;

-- Reservas dos pedidos ainda aguardando pagamento
update product_variants v
   set stock_reserved = least(r.qtd, v.stock_on_hand)
  from (select i.variant_id, sum(i.quantity)::int as qtd
          from orders o join order_items i on i.order_id = o.id
         where o.status = 'aguardando' group by i.variant_id) r
 where r.variant_id = v.id;

-- Cliente não pode ter sido "criado" depois da primeira compra
update customers c
   set created_at = least(c.created_at, f.primeira)
  from (select customer_id, min(created_at) as primeira from (
          select customer_id, created_at from orders where customer_id is not null
          union all
          select customer_id, created_at from pos_sales where customer_id is not null) u
        group by customer_id) f
 where f.customer_id = c.id;

drop table t_cat, t_cli, t_venda, t_prod, t_var, t_linha, t_item, t_total;
