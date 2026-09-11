-- ============================================================
-- 012 — Pedidos de verdade.
--
-- As tabelas `orders` e `order_items` existem desde a 001 mas nunca
-- foram usadas pelo app. Aqui elas passam a ser o registro do pedido
-- que nasce no checkout do site (antes de abrir o WhatsApp) e do
-- pedido lançado à mão pela dona.
-- ============================================================

-- ------------------------------------------------------------
-- orders
-- ------------------------------------------------------------
alter table orders alter column contact_id drop not null;

alter table orders add column if not exists channel         text not null default 'site';
alter table orders add column if not exists customer_id     uuid;
alter table orders add column if not exists subtotal_cents  int  not null default 0;
alter table orders add column if not exists discount_cents  int  not null default 0;
alter table orders add column if not exists shipping_cents  int  not null default 0;
alter table orders add column if not exists total_cents     int  not null default 0;
alter table orders add column if not exists payment_method  text;
alter table orders add column if not exists payment_status  text not null default 'pendente';
alter table orders add column if not exists tracking_code   text;
alter table orders add column if not exists carrier         text;
alter table orders add column if not exists customer_name   text;
alter table orders add column if not exists customer_phone  text;
alter table orders add column if not exists shipping_address jsonb;
alter table orders add column if not exists reserved_until  timestamptz;
alter table orders add column if not exists confirmed_at    timestamptz;
alter table orders add column if not exists cancelled_at    timestamptz;

-- Número legível para a dona e para a cliente ("pedido #1042").
create sequence if not exists orders_number_seq start 1000;
alter table orders add column if not exists order_number int;
update orders set order_number = nextval('orders_number_seq') where order_number is null;
alter table orders alter column order_number set default nextval('orders_number_seq');
alter table orders alter column order_number set not null;

do $do$ begin
  create unique index orders_number_key on orders(order_number);
exception when duplicate_table then null; end $do$;

-- Status: o antigo tinha 4 valores; o novo cobre o ciclo real.
update orders set status = case status
  when 'pending'   then 'aguardando'
  when 'confirmed' then 'confirmado'
  when 'delivered' then 'entregue'
  when 'cancelled' then 'cancelado'
  else status
end;

alter table orders drop constraint if exists orders_status_check;
alter table orders add constraint orders_status_check check (status in (
  'aguardando', 'confirmado', 'pago', 'enviado', 'entregue', 'cancelado', 'devolvido'
));
alter table orders alter column status set default 'aguardando';

do $do$ begin
  alter table orders add constraint orders_channel_check
    check (channel in ('site', 'loja', 'whatsapp'));
exception when duplicate_object then null; end $do$;

do $do$ begin
  alter table orders add constraint orders_payment_status_check
    check (payment_status in ('pendente', 'pago', 'estornado'));
exception when duplicate_object then null; end $do$;

create index if not exists orders_channel_idx     on orders(channel);
create index if not exists orders_created_at_idx  on orders(created_at desc);
create index if not exists orders_reserved_idx    on orders(reserved_until)
  where status = 'aguardando';

-- ------------------------------------------------------------
-- order_items — o item congela o que foi vendido e a que custo.
-- Mudar o preço do produto amanhã não pode alterar o pedido de hoje
-- nem a margem histórica.
-- ------------------------------------------------------------
alter table order_items add column if not exists variant_id            uuid references product_variants(id) on delete restrict;
alter table order_items add column if not exists unit_price_cents      int;
alter table order_items add column if not exists cost_cents_snapshot   int not null default 0;
alter table order_items add column if not exists product_name_snapshot text;
alter table order_items add column if not exists size_snapshot         text;
alter table order_items add column if not exists color_snapshot        text;

-- Backfill do que já existia (a coluna antiga unit_price é numeric em reais).
update order_items set unit_price_cents = round(unit_price * 100)::int
 where unit_price_cents is null;
update order_items set size_snapshot = size where size_snapshot is null;

create index if not exists order_items_variant_idx on order_items(variant_id);

-- ------------------------------------------------------------
-- order_events — histórico de status: quem mudou o quê e quando.
-- ------------------------------------------------------------
create table if not exists order_events (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references orders(id) on delete cascade,
  from_status text,
  to_status   text not null,
  note        text,
  created_by  text not null default 'sistema',
  created_at  timestamptz not null default now()
);

create index if not exists order_events_order_idx on order_events(order_id, created_at desc);

alter table order_events enable row level security;

drop policy if exists "order_events_service_only" on order_events;
create policy "order_events_service_only"
  on order_events for all
  using (auth.role() = 'service_role');

-- ------------------------------------------------------------
-- release_expired_reservations — devolve ao estoque o que ficou
-- reservado em pedido que ninguém confirmou. Roda por cron/job.
-- ------------------------------------------------------------
create or replace function release_expired_reservations()
returns int
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_order record;
  v_item  record;
  v_count int := 0;
begin
  for v_order in
    select id, status from orders
     where status = 'aguardando'
       and reserved_until is not null
       and reserved_until < now()
     for update skip locked
  loop
    for v_item in
      select variant_id, quantity from order_items
       where order_id = v_order.id and variant_id is not null
    loop
      perform release_stock(v_item.variant_id, v_item.quantity);
    end loop;

    update orders
       set status = 'cancelado', cancelled_at = now()
     where id = v_order.id;

    insert into order_events (order_id, from_status, to_status, note, created_by)
    values (v_order.id, 'aguardando', 'cancelado',
            'Cancelado automaticamente: reserva expirou', 'sistema');

    v_count := v_count + 1;
  end loop;

  return v_count;
end $fn$;

-- Pedidos já eram service-role-only na 001; o mesmo vale para os eventos.
revoke all on order_events from anon, authenticated;
