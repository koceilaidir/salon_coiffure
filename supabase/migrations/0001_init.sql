-- =====================================================================
-- Salon de coiffure — schéma initial Supabase
-- Tous les montants sont stockés en CENTIMES (bigint) : 1 500,00 DA = 150000.
-- Aucun arrondi caché : la compta est exacte au centime.
-- À exécuter une fois dans Supabase > SQL Editor (ou `supabase db push`).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Rôles et profils
-- ---------------------------------------------------------------------
do $$ begin
  create type public.user_role as enum ('owner', 'manager');
exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '',
  role public.user_role not null default 'manager',
  can_pay_salaries boolean not null default false,
  created_at timestamptz not null default now()
);

create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid());
$$;

create or replace function public.is_owner() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'owner');
$$;

create or replace function public.can_pay_salaries() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and (role = 'owner' or can_pay_salaries)
  );
$$;

-- Jour "local" du salon (les journées de caisse suivent l'heure d'Alger)
create or replace function public.local_date(ts timestamptz) returns date
language sql immutable as $$
  select (ts at time zone 'Africa/Algiers')::date;
$$;

-- ---------------------------------------------------------------------
-- Réglages du salon (une seule ligne)
-- ---------------------------------------------------------------------
create table if not exists public.salon_settings (
  id smallint primary key default 1 check (id = 1),
  salon_name text not null default 'Mon salon',
  address text not null default '',
  phone text not null default '',
  loyalty_discount_pct numeric(5,2) not null default 0
    check (loyalty_discount_pct between 0 and 100),
  points_per_100_da int not null default 1 check (points_per_100_da >= 0),
  receipt_footer text not null default 'Merci et à bientôt !'
);
insert into public.salon_settings (id) values (1) on conflict do nothing;

-- ---------------------------------------------------------------------
-- Catalogue, employées, clientes, stock
-- ---------------------------------------------------------------------
create table if not exists public.employees (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  base_salary_cents bigint not null default 0 check (base_salary_cents >= 0),
  commission_pct numeric(5,2) not null default 0 check (commission_pct between 0 and 100),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.services (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null default 'Coiffure',
  duration_min int not null default 30 check (duration_min >= 0),
  price_cents bigint not null check (price_cents >= 0),
  active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null default 'Divers',
  unit text not null default 'unité',
  quantity numeric(12,3) not null default 0,
  min_quantity numeric(12,3) not null default 0 check (min_quantity >= 0),
  cost_cents bigint not null default 0 check (cost_cents >= 0),
  sale_price_cents bigint check (sale_price_cents >= 0), -- null = pas vendu aux clientes
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Produits consommés par une prestation (déduits du stock à l'encaissement)
create table if not exists public.service_products (
  service_id uuid not null references public.services (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  quantity numeric(12,3) not null check (quantity > 0),
  primary key (service_id, product_id)
);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text not null default '',
  is_loyal boolean not null default false,
  loyalty_points int not null default 0,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Ventes
-- ---------------------------------------------------------------------
create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  ticket_no bigint generated always as identity unique,
  customer_id uuid references public.customers (id),
  subtotal_cents bigint not null,
  discount_cents bigint not null default 0,
  total_cents bigint not null,
  payment_method text not null check (payment_method in ('cash', 'cib', 'edahabia')),
  paid_cents bigint not null,
  change_cents bigint not null default 0,
  created_by uuid default auth.uid() references auth.users (id),
  created_at timestamptz not null default now(),
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users (id)
);
create index if not exists sales_created_at_idx on public.sales (created_at);

create table if not exists public.sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales (id) on delete cascade,
  kind text not null check (kind in ('service', 'product')),
  service_id uuid references public.services (id),
  product_id uuid references public.products (id),
  employee_id uuid references public.employees (id),
  label text not null,
  quantity int not null default 1 check (quantity > 0),
  unit_price_cents bigint not null,
  total_cents bigint not null
);
create index if not exists sale_items_sale_idx on public.sale_items (sale_id);
create index if not exists sale_items_employee_idx on public.sale_items (employee_id);

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  delta numeric(12,3) not null,
  reason text not null check (reason in ('sale', 'restock', 'adjustment')),
  sale_id uuid references public.sales (id) on delete set null,
  note text not null default '',
  created_by uuid default auth.uid() references auth.users (id),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Dépenses, salaires, clôtures de caisse
-- ---------------------------------------------------------------------
create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  category text not null
    check (category in ('electricite', 'eau', 'loyer', 'fournisseurs', 'entretien', 'autre')),
  amount_cents bigint not null check (amount_cents > 0),
  expense_date date not null default current_date,
  payment_method text not null default 'cash' check (payment_method in ('cash', 'transfer', 'cheque')),
  note text not null default '',
  receipt_path text,
  created_by uuid default auth.uid() references auth.users (id),
  created_at timestamptz not null default now()
);
create index if not exists expenses_date_idx on public.expenses (expense_date);

create table if not exists public.salary_payments (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees (id),
  period_month date not null check (extract(day from period_month) = 1),
  base_cents bigint not null,
  commission_cents bigint not null,
  bonus_cents bigint not null default 0,
  total_cents bigint not null check (total_cents >= 0),
  payment_method text not null default 'cash' check (payment_method in ('cash', 'transfer')),
  paid_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id),
  unique (employee_id, period_month)
);

create table if not exists public.cash_closures (
  id uuid primary key default gen_random_uuid(),
  closure_date date not null unique,
  expected_cents bigint not null,
  counted_cents bigint not null,
  difference_cents bigint generated always as (counted_cents - expected_cents) stored,
  note text not null default '',
  created_by uuid default auth.uid() references auth.users (id),
  created_at timestamptz not null default now()
);

-- Journal : toutes les entrées et sorties d'argent
create or replace view public.ledger with (security_invoker = true) as
  select s.created_at as at, 'sale'::text as kind,
         'Ticket n° ' || s.ticket_no as label,
         s.total_cents as in_cents, 0::bigint as out_cents, s.payment_method
  from public.sales s where s.cancelled_at is null
  union all
  select (e.expense_date::timestamp at time zone 'Africa/Algiers') + interval '12 hours',
         'expense',
         (case e.category
            when 'electricite' then 'Électricité'
            when 'eau' then 'Eau'
            when 'loyer' then 'Loyer'
            when 'fournisseurs' then 'Fournisseurs'
            when 'entretien' then 'Entretien'
            else 'Autre' end)
         || case when e.note <> '' then ' — ' || e.note else '' end,
         0, e.amount_cents, e.payment_method
  from public.expenses e
  union all
  select p.paid_at, 'salary', 'Salaire — ' || em.full_name,
         0, p.total_cents, p.payment_method
  from public.salary_payments p join public.employees em on em.id = p.employee_id;

-- ---------------------------------------------------------------------
-- RLS : la gérante et le propriétaire voient tout ; certaines écritures
-- ne passent que par les fonctions ci-dessous (ventes, paie, clôture, stock).
-- ---------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.salon_settings enable row level security;
alter table public.employees enable row level security;
alter table public.services enable row level security;
alter table public.products enable row level security;
alter table public.service_products enable row level security;
alter table public.customers enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.stock_movements enable row level security;
alter table public.expenses enable row level security;
alter table public.salary_payments enable row level security;
alter table public.cash_closures enable row level security;

create policy "profiles: lire le sien ou tout si proprio" on public.profiles
  for select to authenticated using (id = auth.uid() or public.is_owner());
create policy "profiles: proprio modifie" on public.profiles
  for update to authenticated using (public.is_owner()) with check (public.is_owner());
create policy "profiles: proprio ajoute" on public.profiles
  for insert to authenticated with check (public.is_owner());

create policy "settings: lecture" on public.salon_settings
  for select to authenticated using (public.is_staff());
create policy "settings: proprio modifie" on public.salon_settings
  for update to authenticated using (public.is_owner()) with check (public.is_owner());

-- Tables que la gérante peut lire, créer et modifier
do $$
declare t text;
begin
  foreach t in array array['employees', 'services', 'products', 'service_products', 'customers', 'expenses']
  loop
    execute format('create policy "%1$s: lecture" on public.%1$I for select to authenticated using (public.is_staff())', t);
    execute format('create policy "%1$s: ajout" on public.%1$I for insert to authenticated with check (public.is_staff())', t);
    execute format('create policy "%1$s: modif" on public.%1$I for update to authenticated using (public.is_staff()) with check (public.is_staff())', t);
    execute format('create policy "%1$s: suppression proprio" on public.%1$I for delete to authenticated using (public.is_owner())', t);
  end loop;
end $$;

-- La composition des prestations peut être modifiée par la gérante
create policy "service_products: suppression gérante" on public.service_products
  for delete to authenticated using (public.is_staff());

-- Tables en lecture seule (écriture via fonctions uniquement)
do $$
declare t text;
begin
  foreach t in array array['sales', 'sale_items', 'stock_movements', 'salary_payments', 'cash_closures']
  loop
    execute format('create policy "%1$s: lecture" on public.%1$I for select to authenticated using (public.is_staff())', t);
  end loop;
end $$;

-- La quantité en stock ne change que via les fonctions (traçabilité)
revoke update on public.products from authenticated;
grant update (name, category, unit, min_quantity, cost_cents, sale_price_cents, active)
  on public.products to authenticated;

-- ---------------------------------------------------------------------
-- Fonctions métier
-- ---------------------------------------------------------------------

-- Encaissement : prix lus côté serveur, stock déduit, points fidélité, tout ou rien.
-- p_items : [{"kind":"service","service_id":"…","employee_id":"…","quantity":1},
--            {"kind":"product","product_id":"…","quantity":2}]
create or replace function public.create_sale(
  p_items jsonb,
  p_payment_method text,
  p_paid_cents bigint default null,
  p_customer_id uuid default null
) returns public.sales
language plpgsql security definer set search_path = public as $$
declare
  v_sale public.sales;
  v_item jsonb;
  v_kind text;
  v_qty int;
  v_price bigint;
  v_label text;
  v_service uuid;
  v_product uuid;
  v_sub bigint := 0;
  v_disc bigint := 0;
  v_total bigint;
  v_paid bigint;
  v_loyal boolean := false;
  v_pct numeric;
  v_points_rate int;
begin
  if not public.is_staff() then raise exception 'Accès refusé'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'Le ticket est vide'; end if;
  if p_payment_method not in ('cash', 'cib', 'edahabia') then raise exception 'Mode de paiement invalide'; end if;

  -- 1. Sous-total avec les prix de la base
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_kind := v_item ->> 'kind';
    v_qty := coalesce((v_item ->> 'quantity')::int, 1);
    if v_qty <= 0 then raise exception 'Quantité invalide'; end if;
    v_price := null;
    if v_kind = 'service' then
      select price_cents into v_price from services where id = (v_item ->> 'service_id')::uuid;
    elsif v_kind = 'product' then
      select sale_price_cents into v_price from products where id = (v_item ->> 'product_id')::uuid;
    else
      raise exception 'Type de ligne invalide';
    end if;
    if v_price is null then raise exception 'Article introuvable ou non vendu'; end if;
    v_sub := v_sub + v_price * v_qty;
  end loop;

  -- 2. Remise fidélité
  if p_customer_id is not null then
    select is_loyal into v_loyal from customers where id = p_customer_id;
    if not found then raise exception 'Cliente introuvable'; end if;
  end if;
  select loyalty_discount_pct, points_per_100_da into v_pct, v_points_rate from salon_settings where id = 1;
  if coalesce(v_loyal, false) then
    v_disc := round(v_sub * coalesce(v_pct, 0) / 100.0)::bigint;
  end if;
  v_total := v_sub - v_disc;

  -- 3. Montant reçu (seules les espèces rendent la monnaie)
  if p_payment_method = 'cash' then
    v_paid := coalesce(p_paid_cents, v_total);
    if v_paid < v_total then raise exception 'Montant reçu insuffisant'; end if;
  else
    v_paid := v_total;
  end if;

  insert into sales (customer_id, subtotal_cents, discount_cents, total_cents,
                     payment_method, paid_cents, change_cents)
  values (p_customer_id, v_sub, v_disc, v_total, p_payment_method, v_paid, v_paid - v_total)
  returning * into v_sale;

  -- 4. Lignes + stock
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_kind := v_item ->> 'kind';
    v_qty := coalesce((v_item ->> 'quantity')::int, 1);
    if v_kind = 'service' then
      v_service := (v_item ->> 'service_id')::uuid;
      select price_cents, name into v_price, v_label from services where id = v_service;
      insert into sale_items (sale_id, kind, service_id, employee_id, label, quantity, unit_price_cents, total_cents)
      values (v_sale.id, 'service', v_service, nullif(v_item ->> 'employee_id', '')::uuid,
              v_label, v_qty, v_price, v_price * v_qty);

      insert into stock_movements (product_id, delta, reason, sale_id)
      select sp.product_id, -sp.quantity * v_qty, 'sale', v_sale.id
      from service_products sp where sp.service_id = v_service;

      update products p set quantity = p.quantity - sp.quantity * v_qty
      from service_products sp
      where sp.service_id = v_service and p.id = sp.product_id;
    else
      v_product := (v_item ->> 'product_id')::uuid;
      select sale_price_cents, name into v_price, v_label from products where id = v_product;
      insert into sale_items (sale_id, kind, product_id, employee_id, label, quantity, unit_price_cents, total_cents)
      values (v_sale.id, 'product', v_product, nullif(v_item ->> 'employee_id', '')::uuid,
              v_label, v_qty, v_price, v_price * v_qty);

      insert into stock_movements (product_id, delta, reason, sale_id)
      values (v_product, -v_qty, 'sale', v_sale.id);

      update products set quantity = quantity - v_qty where id = v_product;
    end if;
  end loop;

  -- 5. Points fidélité (par tranche de 100 DA)
  if p_customer_id is not null then
    update customers
       set loyalty_points = loyalty_points + ((v_total / 10000) * coalesce(v_points_rate, 0))::int
     where id = p_customer_id;
  end if;

  return v_sale;
end $$;

-- Entrée de marchandise (delta > 0) ou ajustement d'inventaire
create or replace function public.stock_entry(
  p_product_id uuid,
  p_delta numeric,
  p_reason text default 'restock',
  p_note text default ''
) returns public.products
language plpgsql security definer set search_path = public as $$
declare v public.products;
begin
  if not public.is_staff() then raise exception 'Accès refusé'; end if;
  if p_reason not in ('restock', 'adjustment') then raise exception 'Motif invalide'; end if;
  if p_reason = 'restock' and p_delta <= 0 then raise exception 'La quantité doit être positive'; end if;
  insert into stock_movements (product_id, delta, reason, note)
  values (p_product_id, p_delta, p_reason, coalesce(p_note, ''));
  update products set quantity = quantity + p_delta where id = p_product_id returning * into v;
  if not found then raise exception 'Produit introuvable'; end if;
  return v;
end $$;

-- Paie du mois : fixe + commission sur les prestations réalisées
create or replace function public.payroll_month(p_month date)
returns table (
  employee_id uuid,
  full_name text,
  base_cents bigint,
  services_cents bigint,
  commission_pct numeric,
  commission_cents bigint,
  paid boolean,
  paid_total_cents bigint,
  paid_at timestamptz
)
language sql stable security definer set search_path = public as $$
  with m as (
    select date_trunc('month', p_month)::date as d,
           (date_trunc('month', p_month) + interval '1 month')::date as e
  ),
  s as (
    select si.employee_id as emp, sum(si.total_cents)::bigint as tot
    from sale_items si
    join sales sa on sa.id = si.sale_id
    cross join m
    where si.kind = 'service' and sa.cancelled_at is null
      and public.local_date(sa.created_at) >= m.d
      and public.local_date(sa.created_at) < m.e
    group by si.employee_id
  )
  select e.id, e.full_name, e.base_salary_cents,
         coalesce(s.tot, 0)::bigint,
         e.commission_pct,
         round(coalesce(s.tot, 0) * e.commission_pct / 100.0)::bigint,
         sp.id is not null,
         sp.total_cents,
         sp.paid_at
  from employees e
  cross join m
  left join s on s.emp = e.id
  left join salary_payments sp on sp.employee_id = e.id and sp.period_month = m.d
  where public.is_staff() and (e.active or sp.id is not null)
  order by e.full_name;
$$;

create or replace function public.pay_employee(
  p_employee_id uuid,
  p_month date,
  p_bonus_cents bigint default 0,
  p_method text default 'cash'
) returns public.salary_payments
language plpgsql security definer set search_path = public as $$
declare
  r record;
  v public.salary_payments;
  v_month date := date_trunc('month', p_month)::date;
begin
  if not public.can_pay_salaries() then
    raise exception 'Ce compte n''a pas le droit de payer les salaires';
  end if;
  select * into r from public.payroll_month(v_month) pm where pm.employee_id = p_employee_id;
  if not found then raise exception 'Employée introuvable'; end if;
  if r.paid then raise exception 'Le salaire de ce mois est déjà payé'; end if;
  insert into salary_payments (employee_id, period_month, base_cents, commission_cents,
                               bonus_cents, total_cents, payment_method)
  values (p_employee_id, v_month, r.base_cents, r.commission_cents, coalesce(p_bonus_cents, 0),
          r.base_cents + r.commission_cents + coalesce(p_bonus_cents, 0), p_method)
  returning * into v;
  return v;
end $$;

-- Synthèse du mois
create or replace function public.month_summary(p_month date)
returns table (
  revenue_cents bigint,
  tickets int,
  expenses_cents bigint,
  salaries_cents bigint,
  net_cents bigint
)
language plpgsql stable security definer set search_path = public as $$
declare
  d date := date_trunc('month', p_month)::date;
  e date := (date_trunc('month', p_month) + interval '1 month')::date;
  v_rev bigint; v_tix int; v_exp bigint; v_sal bigint;
begin
  if not public.is_staff() then raise exception 'Accès refusé'; end if;
  select coalesce(sum(total_cents), 0), count(*) into v_rev, v_tix
    from sales where cancelled_at is null
     and public.local_date(created_at) >= d and public.local_date(created_at) < e;
  select coalesce(sum(amount_cents), 0) into v_exp
    from expenses where expense_date >= d and expense_date < e;
  select coalesce(sum(total_cents), 0) into v_sal
    from salary_payments where period_month = d;
  return query select v_rev, v_tix, v_exp, v_sal, v_rev - v_exp - v_sal;
end $$;

-- Caisse du jour : fond de caisse (dernier comptage) + espèces entrées - sorties
create or replace function public.cash_day(p_date date)
returns table (
  opening_cents bigint,
  sales_cash_cents bigint,
  expenses_cash_cents bigint,
  salaries_cash_cents bigint,
  expected_cents bigint,
  closed boolean,
  counted_cents bigint
)
language plpgsql stable security definer set search_path = public as $$
declare
  v_open bigint; v_s bigint; v_e bigint; v_p bigint;
  v_counted bigint; v_closed boolean;
begin
  if not public.is_staff() then raise exception 'Accès refusé'; end if;
  select c.counted_cents into v_open from cash_closures c
   where c.closure_date < p_date order by c.closure_date desc limit 1;
  v_open := coalesce(v_open, 0);
  select coalesce(sum(total_cents), 0) into v_s from sales
   where cancelled_at is null and payment_method = 'cash' and public.local_date(created_at) = p_date;
  select coalesce(sum(amount_cents), 0) into v_e from expenses
   where payment_method = 'cash' and expense_date = p_date;
  select coalesce(sum(total_cents), 0) into v_p from salary_payments
   where payment_method = 'cash' and public.local_date(paid_at) = p_date;
  select c.counted_cents into v_counted from cash_closures c where c.closure_date = p_date;
  v_closed := found;
  return query select v_open, v_s, v_e, v_p, v_open + v_s - v_e - v_p, v_closed, v_counted;
end $$;

create or replace function public.close_day(
  p_date date,
  p_counted_cents bigint,
  p_note text default ''
) returns public.cash_closures
language plpgsql security definer set search_path = public as $$
declare
  r record;
  v public.cash_closures;
begin
  if not public.is_staff() then raise exception 'Accès refusé'; end if;
  select * into r from public.cash_day(p_date);
  if r.closed then raise exception 'Cette journée est déjà clôturée'; end if;
  insert into cash_closures (closure_date, expected_cents, counted_cents, note)
  values (p_date, r.expected_cents, p_counted_cents, coalesce(p_note, ''))
  returning * into v;
  return v;
end $$;

-- Les fonctions ne sont appelables que par un utilisateur connecté
revoke execute on function public.create_sale(jsonb, text, bigint, uuid) from public, anon;
revoke execute on function public.stock_entry(uuid, numeric, text, text) from public, anon;
revoke execute on function public.payroll_month(date) from public, anon;
revoke execute on function public.pay_employee(uuid, date, bigint, text) from public, anon;
revoke execute on function public.month_summary(date) from public, anon;
revoke execute on function public.cash_day(date) from public, anon;
revoke execute on function public.close_day(date, bigint, text) from public, anon;
grant execute on function public.create_sale(jsonb, text, bigint, uuid) to authenticated;
grant execute on function public.stock_entry(uuid, numeric, text, text) to authenticated;
grant execute on function public.payroll_month(date) to authenticated;
grant execute on function public.pay_employee(uuid, date, bigint, text) to authenticated;
grant execute on function public.month_summary(date) to authenticated;
grant execute on function public.cash_day(date) to authenticated;
grant execute on function public.close_day(date, bigint, text) to authenticated;

-- ---------------------------------------------------------------------
-- Stockage des photos de factures
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('expense-receipts', 'expense-receipts', false)
on conflict (id) do nothing;

create policy "factures: lecture équipe" on storage.objects
  for select to authenticated using (bucket_id = 'expense-receipts' and public.is_staff());
create policy "factures: envoi équipe" on storage.objects
  for insert to authenticated with check (bucket_id = 'expense-receipts' and public.is_staff());
