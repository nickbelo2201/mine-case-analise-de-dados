-- ============================================================
-- 011 — Estoque: movimentações e as funções que são a ÚNICA porta
--       de escrita do saldo.
--
-- Regra do sistema: nenhum código de aplicação faz UPDATE em
-- stock_on_hand ou stock_reserved. Tudo passa por estas funções,
-- que gravam o movimento e ajustam o saldo na mesma transação.
-- ============================================================

create table if not exists stock_movements (
  id          uuid primary key default gen_random_uuid(),
  variant_id  uuid not null references product_variants(id) on delete restrict,
  delta       int  not null check (delta <> 0),   -- + entrada / − saída
  reason      text not null check (reason in (
                'venda_online', 'venda_loja', 'devolucao', 'perda', 'ajuste',
                'entrada_compra', 'inventario', 'transferencia', 'mostruario'
              )),
  -- Origem do movimento: 'order' / 'pos_sale' / 'purchase' / 'inventory'
  ref_type    text,
  ref_id      uuid,
  note        text,
  created_by  text not null default 'sistema',
  created_at  timestamptz not null default now()
);

create index if not exists stock_movements_variant_idx on stock_movements(variant_id, created_at desc);
create index if not exists stock_movements_reason_idx  on stock_movements(reason);
create index if not exists stock_movements_created_idx on stock_movements(created_at desc);

-- Idempotência: um mesmo pedido não pode baixar o mesmo item duas vezes.
create unique index if not exists stock_movements_ref_unique
  on stock_movements(ref_type, ref_id, variant_id, reason)
  where ref_id is not null;

alter table stock_movements enable row level security;

drop policy if exists "stock_movements_service_only" on stock_movements;
create policy "stock_movements_service_only"
  on stock_movements for all
  using (auth.role() = 'service_role');

-- ------------------------------------------------------------
-- apply_stock_movement — grava o movimento e ajusta o saldo.
-- Recusa se levaria o saldo a negativo, exceto em 'ajuste'/'inventario',
-- onde o número contado é a verdade (mas nunca abaixo de zero).
-- ------------------------------------------------------------
create or replace function apply_stock_movement(
  p_variant_id uuid,
  p_delta      int,
  p_reason     text,
  p_ref_type   text default null,
  p_ref_id     uuid default null,
  p_note       text default null,
  p_by         text default 'sistema'
) returns uuid
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_id  uuid;
  v_new int;
begin
  if p_delta = 0 then
    raise exception 'Movimento de estoque com quantidade zero.';
  end if;

  -- Trava a linha para serializar movimentos concorrentes na mesma variante.
  select stock_on_hand + p_delta into v_new
    from product_variants
   where id = p_variant_id
     for update;

  if not found then
    raise exception 'Variante % não encontrada.', p_variant_id;
  end if;

  if v_new < 0 then
    if p_reason in ('ajuste', 'inventario') then
      v_new := 0;
    else
      raise exception 'Estoque insuficiente: a operação deixaria o saldo negativo.'
        using errcode = 'check_violation';
    end if;
  end if;

  update product_variants
     set stock_on_hand = v_new,
         updated_at    = now()
   where id = p_variant_id;

  insert into stock_movements (variant_id, delta, reason, ref_type, ref_id, note, created_by)
  values (p_variant_id, p_delta, p_reason, p_ref_type, p_ref_id, p_note, p_by)
  returning id into v_id;

  return v_id;
end $fn$;

-- ------------------------------------------------------------
-- reserve_stock — a trava anti-oversell.
-- O UPDATE condicional é atômico: se afetou 0 linhas, não havia saldo.
-- Nunca lê o saldo na aplicação para depois gravar.
-- ------------------------------------------------------------
create or replace function reserve_stock(
  p_variant_id uuid,
  p_qty        int,
  p_channel    text default 'site'
) returns boolean
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_safety int := 0;
  v_rows   int;
begin
  if p_qty <= 0 then
    raise exception 'Quantidade inválida para reserva.';
  end if;

  if p_channel = 'site' then
    select site_safety_stock into v_safety from store_settings where id = 1;
  end if;

  update product_variants v
     set stock_reserved = v.stock_reserved + p_qty,
         updated_at     = now()
    from products p
   where v.id = p_variant_id
     and p.id = v.product_id
     and v.active
     and (p_channel <> 'site' or p.status = 'ativo')
     and v.stock_on_hand - v.stock_reserved - coalesce(v_safety, 0) >= p_qty;

  get diagnostics v_rows = row_count;
  return v_rows > 0;
end $fn$;

-- ------------------------------------------------------------
-- release_stock — devolve a reserva (pedido cancelado ou expirado).
-- ------------------------------------------------------------
create or replace function release_stock(
  p_variant_id uuid,
  p_qty        int
) returns void
language plpgsql
security definer
set search_path = public
as $fn$
begin
  update product_variants
     set stock_reserved = greatest(stock_reserved - p_qty, 0),
         updated_at     = now()
   where id = p_variant_id;
end $fn$;

-- ------------------------------------------------------------
-- commit_reservation — libera a reserva e aplica a saída definitiva,
-- numa transação só. Idempotente por (ref_type, ref_id, variante).
-- ------------------------------------------------------------
create or replace function commit_reservation(
  p_variant_id uuid,
  p_qty        int,
  p_reason     text,
  p_ref_type   text,
  p_ref_id     uuid,
  p_by         text default 'sistema'
) returns uuid
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_existing uuid;
begin
  select id into v_existing
    from stock_movements
   where ref_type = p_ref_type and ref_id = p_ref_id
     and variant_id = p_variant_id and reason = p_reason;

  if v_existing is not null then
    return v_existing;   -- já baixado: clicar duas vezes não dobra nada
  end if;

  perform release_stock(p_variant_id, p_qty);
  return apply_stock_movement(
    p_variant_id, -p_qty, p_reason, p_ref_type, p_ref_id, null, p_by
  );
end $fn$;

-- ------------------------------------------------------------
-- check_stock_integrity — rede de segurança contra bug de código.
-- A soma das movimentações tem que bater com o saldo materializado.
-- ------------------------------------------------------------
create or replace function check_stock_integrity()
returns table (
  variant_id     uuid,
  sku            text,
  saldo_atual    int,
  soma_movimentos int,
  divergencia    int
)
language sql
stable
as $fn$
  select v.id,
         v.sku,
         v.stock_on_hand,
         coalesce(m.total, 0)::int,
         v.stock_on_hand - coalesce(m.total, 0)::int
    from product_variants v
    left join (
      select variant_id, sum(delta) as total
        from stock_movements
       group by variant_id
    ) m on m.variant_id = v.id
   where v.stock_on_hand <> coalesce(m.total, 0);
$fn$;

-- ------------------------------------------------------------
-- Lançamento inicial: o saldo que veio da migração precisa existir
-- como movimento, senão a conferência de integridade acusa tudo.
-- ------------------------------------------------------------
insert into stock_movements (variant_id, delta, reason, ref_type, ref_id, note, created_by)
select v.id, v.stock_on_hand, 'inventario', 'migration',
       '00000000-0000-0000-0000-000000000010'::uuid,
       'Saldo inicial migrado do cadastro antigo', 'migracao'
  from product_variants v
 where v.stock_on_hand > 0
on conflict do nothing;

-- O histórico de estoque é interno.
revoke all on stock_movements from anon, authenticated;
