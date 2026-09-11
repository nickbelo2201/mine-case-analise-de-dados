-- ============================================================
-- 013 — Clientes.
--
-- Chave real do cliente no varejo brasileiro é o WhatsApp. Ele é
-- guardado normalizado (E.164, só dígitos com DDI) — sem isso,
-- "(11) 98888-7777", "11988887777" e "5511988887777" viram três
-- clientes e o histórico se fragmenta.
--
-- `contacts` (funil WhatsApp/n8n) continua existindo e separado;
-- a ponte entre os dois é o número normalizado.
-- ============================================================

create or replace function normalize_phone(raw text)
returns text
language plpgsql
immutable
as $fn$
declare
  d text;
begin
  if raw is null then return null; end if;
  d := regexp_replace(raw, '[^0-9]', '', 'g');
  if d = '' then return null; end if;

  -- 10 ou 11 dígitos = número nacional sem DDI; assume Brasil.
  if length(d) in (10, 11) then
    d := '55' || d;
  end if;

  return d;
end $fn$;

create table if not exists customers (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  whatsapp      text not null unique,   -- normalizado por normalize_phone
  email         text,
  cpf           text,
  birthdate     date,
  -- Manequim e preferências: tudo opcional, preenchido aos poucos.
  -- { "blusa": "M", "calca": "40", "gosta": "...", "evita": "..." }
  measurements  jsonb not null default '{}',
  tags          text[] not null default '{}',
  notes         text,
  accepts_marketing boolean not null default false,
  source        text,                   -- 'site' | 'loja' | 'whatsapp' | 'importado'
  anonymized_at timestamptz,            -- LGPD: anonimiza, nunca apaga
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- whatsapp já ganha índice pelo unique da coluna
create index if not exists customers_name_idx      on customers(name);
create index if not exists customers_birthdate_idx on customers(birthdate);

do $do$ begin
  alter table orders
    add constraint orders_customer_fk
    foreign key (customer_id) references customers(id) on delete set null;
exception when duplicate_object then null; end $do$;

alter table customers enable row level security;

drop policy if exists "customers_service_only" on customers;
create policy "customers_service_only"
  on customers for all
  using (auth.role() = 'service_role');

-- ------------------------------------------------------------
-- upsert_customer — usado pelo checkout e pelo PDV.
-- Encontra pelo WhatsApp normalizado ou cria; nunca duplica.
-- ------------------------------------------------------------
create or replace function upsert_customer(
  p_name     text,
  p_whatsapp text,
  p_source   text default 'site'
) returns uuid
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_phone text := normalize_phone(p_whatsapp);
  v_id    uuid;
begin
  if v_phone is null then return null; end if;

  insert into customers (name, whatsapp, source)
  values (coalesce(nullif(trim(p_name), ''), 'Cliente ' || right(v_phone, 4)), v_phone, p_source)
  on conflict (whatsapp) do update
    set name       = case when customers.name like 'Cliente %'
                            and nullif(trim(p_name), '') is not null
                          then p_name else customers.name end,
        updated_at = now()
  returning id into v_id;

  return v_id;
end $fn$;

-- ------------------------------------------------------------
-- Visão consolidada: compras do site + do balcão na mesma ficha.
-- ------------------------------------------------------------
create or replace view customer_stats as
select c.id                                            as customer_id,
       count(o.id) filter (where o.status not in ('cancelado'))          as compras,
       coalesce(sum(o.total_cents) filter (
         where o.status in ('confirmado','pago','enviado','entregue')), 0)::int as total_gasto_cents,
       max(o.created_at) filter (where o.status <> 'cancelado')          as ultima_compra
  from customers c
  left join orders o on o.customer_id = c.id
 group by c.id;

-- Dado de cliente nunca é público.
revoke all on customers      from anon, authenticated;
revoke all on customer_stats from anon, authenticated;
