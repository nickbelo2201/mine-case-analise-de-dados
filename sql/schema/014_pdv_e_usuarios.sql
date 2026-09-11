-- ============================================================
-- 014 — PDV (venda de balcão), caixa, usuários com papel e auditoria.
-- ============================================================

-- ------------------------------------------------------------
-- Usuários do admin — senha com hash, não mais em variável de ambiente
-- ------------------------------------------------------------
create table if not exists admin_users (
  id            uuid primary key default gen_random_uuid(),
  email         text not null unique,
  name          text not null,
  password_hash text not null,
  role          text not null default 'vendedora'
                  check (role in ('dona', 'vendedora', 'estoquista')),
  active        boolean not null default true,
  last_login_at timestamptz,
  created_at    timestamptz not null default now()
);

alter table admin_users enable row level security;

drop policy if exists "admin_users_service_only" on admin_users;
create policy "admin_users_service_only"
  on admin_users for all
  using (auth.role() = 'service_role');

create or replace function set_admin_password(p_email text, p_plain text)
returns void
language sql
security definer
set search_path = public, extensions
as $fn$
  update admin_users
     set password_hash = crypt(p_plain, gen_salt('bf', 10))
   where lower(email) = lower(p_email);
$fn$;

create or replace function verify_admin_password(p_email text, p_plain text)
returns table (id uuid, email text, name text, role text)
language sql
security definer
set search_path = public, extensions
as $fn$
  select u.id, u.email, u.name, u.role
    from admin_users u
   where lower(u.email) = lower(p_email)
     and u.active
     and u.password_hash = crypt(p_plain, u.password_hash);
$fn$;

-- ------------------------------------------------------------
-- Auditoria — quem fez o quê, quando, valor antes/depois.
-- Obrigatória em estoque, preço, desconto, cancelamento e exclusão.
-- ------------------------------------------------------------
create table if not exists audit_log (
  id          uuid primary key default gen_random_uuid(),
  actor       text not null,
  action      text not null,          -- 'update' | 'delete' | 'cancel' | 'discount' | ...
  entity      text not null,          -- 'product' | 'variant' | 'order' | 'pos_sale' | ...
  entity_id   uuid,
  before      jsonb,
  after       jsonb,
  note        text,
  created_at  timestamptz not null default now()
);

create index if not exists audit_log_entity_idx  on audit_log(entity, entity_id, created_at desc);
create index if not exists audit_log_created_idx on audit_log(created_at desc);

alter table audit_log enable row level security;

drop policy if exists "audit_log_service_only" on audit_log;
create policy "audit_log_service_only"
  on audit_log for all
  using (auth.role() = 'service_role');

-- ------------------------------------------------------------
-- Caixa
-- ------------------------------------------------------------
create table if not exists cash_sessions (
  id              uuid primary key default gen_random_uuid(),
  opened_by       text not null,
  opened_at       timestamptz not null default now(),
  opening_cents   int  not null default 0,   -- fundo de troco
  closed_by       text,
  closed_at       timestamptz,
  counted_cents   int,                       -- dinheiro contado na gaveta
  expected_cents  int,                       -- o que o sistema esperava
  difference_cents int,
  note            text
);

create index if not exists cash_sessions_open_idx on cash_sessions(closed_at)
  where closed_at is null;

-- Sangria e suprimento
create table if not exists cash_movements (
  id          uuid primary key default gen_random_uuid(),
  session_id  uuid not null references cash_sessions(id) on delete cascade,
  kind        text not null check (kind in ('sangria', 'suprimento')),
  amount_cents int not null check (amount_cents > 0),
  reason      text,
  created_by  text not null default 'sistema',
  created_at  timestamptz not null default now()
);

-- ------------------------------------------------------------
-- Vendas de balcão
-- ------------------------------------------------------------
create table if not exists pos_sales (
  id              uuid primary key default gen_random_uuid(),
  sale_number     int,
  session_id      uuid references cash_sessions(id) on delete set null,
  customer_id     uuid references customers(id) on delete set null,
  seller          text not null,
  subtotal_cents  int not null default 0,
  discount_cents  int not null default 0,
  total_cents     int not null default 0,
  cost_cents      int not null default 0,   -- CMV congelado da venda
  status          text not null default 'concluida'
                    check (status in ('concluida', 'cancelada')),
  cancelled_by    text,
  cancelled_at    timestamptz,
  cancel_reason   text,
  discount_authorized_by text,              -- quem liberou desconto acima do teto
  note            text,
  created_at      timestamptz not null default now()
);

create sequence if not exists pos_sales_number_seq start 1;
alter table pos_sales alter column sale_number set default nextval('pos_sales_number_seq');

create index if not exists pos_sales_created_idx  on pos_sales(created_at desc);
create index if not exists pos_sales_session_idx  on pos_sales(session_id);
create index if not exists pos_sales_customer_idx on pos_sales(customer_id);

create table if not exists pos_sale_items (
  id                    uuid primary key default gen_random_uuid(),
  sale_id               uuid not null references pos_sales(id) on delete cascade,
  variant_id            uuid not null references product_variants(id) on delete restrict,
  quantity              int  not null check (quantity > 0),
  unit_price_cents      int  not null,
  discount_cents        int  not null default 0,
  cost_cents_snapshot   int  not null default 0,
  product_name_snapshot text,
  size_snapshot         text,
  color_snapshot        text
);

create index if not exists pos_sale_items_sale_idx on pos_sale_items(sale_id);

-- Pagamento dividido: metade PIX, metade cartão.
-- A taxa da maquininha fica registrada aqui, senão o "faturamento" mente 3-5%.
create table if not exists pos_payments (
  id            uuid primary key default gen_random_uuid(),
  sale_id       uuid not null references pos_sales(id) on delete cascade,
  method        text not null check (method in (
                  'dinheiro', 'pix', 'debito', 'credito', 'credito_parcelado', 'vale_troca'
                )),
  amount_cents  int not null check (amount_cents > 0),
  installments  int not null default 1,
  fee_cents     int not null default 0,
  brand         text
);

create index if not exists pos_payments_sale_idx on pos_payments(sale_id);

alter table cash_sessions  enable row level security;
alter table cash_movements enable row level security;
alter table pos_sales      enable row level security;
alter table pos_sale_items enable row level security;
alter table pos_payments   enable row level security;

do $do$
declare t text;
begin
  foreach t in array array['cash_sessions','cash_movements','pos_sales','pos_sale_items','pos_payments']
  loop
    execute format('drop policy if exists %I on %I', t || '_service_only', t);
    execute format(
      'create policy %I on %I for all using (auth.role() = ''service_role'')',
      t || '_service_only', t
    );
  end loop;
end $do$;

-- Nada aqui é público: vendas, caixa, usuários e auditoria.
revoke all on admin_users, audit_log, cash_sessions, cash_movements,
              pos_sales, pos_sale_items, pos_payments
         from anon, authenticated;
