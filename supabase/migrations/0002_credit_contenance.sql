-- =====================================================================
-- 0002 — Crédit des clientes + contenance des produits
-- À exécuter APRÈS 0001 (SQL Editor, ou automatiquement via l'intégration GitHub).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Contenance des produits
--    Le stock reste compté en conditionnements (flacons, tubes…), avec des
--    décimales : 2,35 flacons = 2 flacons pleins + 350 ml d'un flacon de 1 L.
--    Chaque produit a une contenance exprimée en ml, g ou pièces.
-- ---------------------------------------------------------------------
alter table public.products alter column quantity type numeric(14,6);
alter table public.stock_movements alter column delta type numeric(14,6);

alter table public.products
  add column if not exists content_amount numeric(12,3) not null default 1,
  add column if not exists content_unit text not null default 'pièce';

do $$ begin
  alter table public.products add constraint products_content_amount_check check (content_amount > 0);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.products add constraint products_content_unit_check check (content_unit in ('ml', 'g', 'pièce'));
exception when duplicate_object then null; end $$;

grant update (content_amount, content_unit) on public.products to authenticated;

-- La consommation d'une prestation est désormais en ml / g / pièces
-- (ex. 30 ml de shampoing). Les anciennes valeurs étaient en conditionnements.
update public.service_products sp
   set quantity = sp.quantity * p.content_amount
  from public.products p
 where p.id = sp.product_id and p.content_amount <> 1;

-- ---------------------------------------------------------------------
-- 2. Crédit des clientes
-- ---------------------------------------------------------------------
alter table public.customers
  add column if not exists credit_cents bigint not null default 0;

-- Le crédit et les points ne changent que via les fonctions (traçabilité)
revoke update on public.customers from authenticated;
grant update (full_name, phone, is_loyal) on public.customers to authenticated;

alter table public.sales
  add column if not exists debt_before_cents bigint not null default 0,   -- crédit de la cliente avant ce ticket
  add column if not exists debt_settled_cents bigint not null default 0,  -- ancien crédit ajouté à ce ticket
  add column if not exists credit_cents bigint not null default 0;        -- reste dû laissé sur ce ticket

create table if not exists public.customer_credit_movements (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  sale_id uuid references public.sales (id) on delete set null,
  delta_cents bigint not null,          -- + la cliente doit plus, - elle a remboursé
  kind text not null check (kind in ('sale_credit', 'sale_settlement', 'repayment')),
  payment_method text,
  note text not null default '',
  created_by uuid default auth.uid() references auth.users (id),
  created_at timestamptz not null default now()
);
create index if not exists ccm_customer_idx on public.customer_credit_movements (customer_id, created_at);

alter table public.customer_credit_movements enable row level security;
create policy "customer_credit_movements: lecture" on public.customer_credit_movements
  for select to authenticated using (public.is_staff());

-- ---------------------------------------------------------------------
-- 3. Encaissement (remplace la version 0001)
-- ---------------------------------------------------------------------
drop function if exists public.create_sale(jsonb, text, bigint, uuid);

create or replace function public.create_sale(
  p_items jsonb,
  p_payment_method text,
  p_paid_cents bigint default null,      -- montant reçu (null = tout le montant dû)
  p_customer_id uuid default null,
  p_settle_debt boolean default true     -- ajouter l'ancien crédit de la cliente à ce ticket
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
  v_loyal boolean := false;
  v_debt_before bigint := 0;
  v_settle bigint := 0;
  v_due bigint;
  v_paid bigint;
  v_change bigint := 0;
  v_credit bigint := 0;
  v_pct numeric;
  v_points_rate int;
begin
  if not public.is_staff() then raise exception 'Accès refusé'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'Le ticket est vide'; end if;
  if p_payment_method not in ('cash', 'cib', 'edahabia') then raise exception 'Mode de paiement invalide'; end if;

  -- Sous-total avec les prix de la base
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

  -- Cliente : fidélité et crédit en cours (verrouillée pendant l'encaissement)
  if p_customer_id is not null then
    select is_loyal, credit_cents into v_loyal, v_debt_before
      from customers where id = p_customer_id for update;
    if not found then raise exception 'Cliente introuvable'; end if;
  end if;
  select loyalty_discount_pct, points_per_100_da into v_pct, v_points_rate from salon_settings where id = 1;
  if coalesce(v_loyal, false) then
    v_disc := round(v_sub * coalesce(v_pct, 0) / 100.0)::bigint;
  end if;
  v_total := v_sub - v_disc;

  if coalesce(p_settle_debt, true) and v_debt_before > 0 then
    v_settle := v_debt_before;
  end if;
  v_due := v_total + v_settle;

  -- Paiement : complet, avec monnaie rendue, ou partiel (reste en crédit)
  v_paid := coalesce(p_paid_cents, v_due);
  if v_paid < 0 then raise exception 'Montant reçu invalide'; end if;
  if v_paid >= v_due then
    if p_payment_method = 'cash' then
      v_change := v_paid - v_due;
    elsif v_paid > v_due then
      raise exception 'Un paiement par carte ne peut pas dépasser le montant dû';
    end if;
  else
    if p_customer_id is null then
      raise exception 'Choisissez la cliente pour lui laisser le reste en crédit';
    end if;
    v_credit := v_due - v_paid;
  end if;

  insert into sales (customer_id, subtotal_cents, discount_cents, total_cents, payment_method,
                     paid_cents, change_cents, debt_before_cents, debt_settled_cents, credit_cents)
  values (p_customer_id, v_sub, v_disc, v_total, p_payment_method,
          v_paid, v_change, v_debt_before, v_settle, v_credit)
  returning * into v_sale;

  -- Lignes + stock (consommation en ml/g/pièces convertie en conditionnements)
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
      select sp.product_id, -(sp.quantity * v_qty) / p.content_amount, 'sale', v_sale.id
        from service_products sp join products p on p.id = sp.product_id
       where sp.service_id = v_service;

      update products p set quantity = p.quantity - (sp.quantity * v_qty) / p.content_amount
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

  -- Crédit et points de la cliente
  if p_customer_id is not null then
    if v_settle > 0 then
      insert into customer_credit_movements (customer_id, sale_id, delta_cents, kind, payment_method, note)
      values (p_customer_id, v_sale.id, -v_settle, 'sale_settlement', p_payment_method,
              'Ancien crédit ajouté au ticket n° ' || v_sale.ticket_no);
    end if;
    if v_credit > 0 then
      insert into customer_credit_movements (customer_id, sale_id, delta_cents, kind, payment_method, note)
      values (p_customer_id, v_sale.id, v_credit, 'sale_credit', p_payment_method,
              'Reste dû sur le ticket n° ' || v_sale.ticket_no);
    end if;
    update customers
       set credit_cents = credit_cents - v_settle + v_credit,
           loyalty_points = loyalty_points + ((v_total / 10000) * coalesce(v_points_rate, 0))::int
     where id = p_customer_id;
  end if;

  return v_sale;
end $$;

-- Remboursement d'un crédit sans nouvelle prestation
create or replace function public.repay_credit(
  p_customer_id uuid,
  p_amount_cents bigint,
  p_payment_method text default 'cash',
  p_note text default ''
) returns public.customers
language plpgsql security definer set search_path = public as $$
declare
  v_balance bigint;
  v public.customers;
begin
  if not public.is_staff() then raise exception 'Accès refusé'; end if;
  if p_payment_method not in ('cash', 'cib', 'edahabia') then raise exception 'Mode de paiement invalide'; end if;
  select credit_cents into v_balance from customers where id = p_customer_id for update;
  if not found then raise exception 'Cliente introuvable'; end if;
  if p_amount_cents is null or p_amount_cents <= 0 then raise exception 'Montant invalide'; end if;
  if p_amount_cents > v_balance then raise exception 'Le montant dépasse le crédit de la cliente'; end if;
  insert into customer_credit_movements (customer_id, delta_cents, kind, payment_method, note)
  values (p_customer_id, -p_amount_cents, 'repayment', p_payment_method, coalesce(p_note, ''));
  update customers set credit_cents = credit_cents - p_amount_cents where id = p_customer_id returning * into v;
  return v;
end $$;

-- ---------------------------------------------------------------------
-- 4. Journal, synthèse et caisse : l'argent réellement reçu
-- ---------------------------------------------------------------------
create or replace view public.ledger with (security_invoker = true) as
  select s.created_at as at, 'sale'::text as kind,
         'Ticket n° ' || s.ticket_no
           || case when s.credit_cents > 0 then ' (reste dû en crédit)' else '' end
           || case when s.debt_settled_cents > 0 then ' (avec ancien crédit)' else '' end as label,
         (s.paid_cents - s.change_cents) as in_cents, 0::bigint as out_cents, s.payment_method
  from public.sales s where s.cancelled_at is null
  union all
  select m.created_at, 'repayment', 'Remboursement crédit — ' || c.full_name,
         -m.delta_cents, 0, m.payment_method
  from public.customer_credit_movements m join public.customers c on c.id = m.customer_id
  where m.kind = 'repayment'
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

drop function if exists public.month_summary(date);
create or replace function public.month_summary(p_month date)
returns table (
  revenue_cents bigint,            -- chiffre d'affaires (valeur des tickets)
  tickets int,
  received_cents bigint,           -- argent réellement encaissé (tickets + remboursements)
  expenses_cents bigint,
  salaries_cents bigint,
  net_cents bigint,                -- chiffre d'affaires - dépenses - salaires
  credit_outstanding_cents bigint  -- total des crédits clientes en cours (aujourd'hui)
)
language plpgsql stable security definer set search_path = public as $$
declare
  d date := date_trunc('month', p_month)::date;
  e date := (date_trunc('month', p_month) + interval '1 month')::date;
  v_rev bigint; v_tix int; v_rec bigint; v_rep bigint; v_exp bigint; v_sal bigint; v_cred bigint;
begin
  if not public.is_staff() then raise exception 'Accès refusé'; end if;
  select coalesce(sum(total_cents), 0), count(*), coalesce(sum(paid_cents - change_cents), 0)
    into v_rev, v_tix, v_rec
    from sales where cancelled_at is null
     and public.local_date(created_at) >= d and public.local_date(created_at) < e;
  select coalesce(sum(-delta_cents), 0) into v_rep
    from customer_credit_movements
   where kind = 'repayment'
     and public.local_date(created_at) >= d and public.local_date(created_at) < e;
  select coalesce(sum(amount_cents), 0) into v_exp
    from expenses where expense_date >= d and expense_date < e;
  select coalesce(sum(total_cents), 0) into v_sal
    from salary_payments where period_month = d;
  select coalesce(sum(credit_cents), 0) into v_cred from customers;
  return query select v_rev, v_tix, v_rec + v_rep, v_exp, v_sal, v_rev - v_exp - v_sal, v_cred;
end $$;

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
  v_open bigint; v_s bigint; v_r bigint; v_e bigint; v_p bigint;
  v_counted bigint; v_closed boolean;
begin
  if not public.is_staff() then raise exception 'Accès refusé'; end if;
  select c.counted_cents into v_open from cash_closures c
   where c.closure_date < p_date order by c.closure_date desc limit 1;
  v_open := coalesce(v_open, 0);
  -- espèces réellement gardées : montant reçu - monnaie rendue
  select coalesce(sum(paid_cents - change_cents), 0) into v_s from sales
   where cancelled_at is null and payment_method = 'cash' and public.local_date(created_at) = p_date;
  select coalesce(sum(-delta_cents), 0) into v_r from customer_credit_movements
   where kind = 'repayment' and payment_method = 'cash' and public.local_date(created_at) = p_date;
  select coalesce(sum(amount_cents), 0) into v_e from expenses
   where payment_method = 'cash' and expense_date = p_date;
  select coalesce(sum(total_cents), 0) into v_p from salary_payments
   where payment_method = 'cash' and public.local_date(paid_at) = p_date;
  select c.counted_cents into v_counted from cash_closures c where c.closure_date = p_date;
  v_closed := found;
  return query select v_open, v_s + v_r, v_e, v_p, v_open + v_s + v_r - v_e - v_p, v_closed, v_counted;
end $$;

revoke execute on function public.create_sale(jsonb, text, bigint, uuid, boolean) from public, anon;
revoke execute on function public.repay_credit(uuid, bigint, text, text) from public, anon;
revoke execute on function public.month_summary(date) from public, anon;
grant execute on function public.create_sale(jsonb, text, bigint, uuid, boolean) to authenticated;
grant execute on function public.repay_credit(uuid, bigint, text, text) to authenticated;
grant execute on function public.month_summary(date) to authenticated;
