-- SchrammScape production schema (stage 1)
-- Multi-user: profiles with roles; work_records carry assigned_to.
-- Sync model: client-generated uuid ids, updated_at (trigger), soft deletes.

-- The original web-app tables are superseded by the app's data.
drop table if exists public.customers;
drop table if exists public.reference_customers;

-- Shared trigger: keep updated_at current on every write.
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------- profiles
create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  role text not null default 'crew' check (role in ('admin', 'manager', 'crew')),
  updated_at timestamptz not null default now()
);
create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

-- Helper: the caller's role (used by RLS policies).
create or replace function public.current_role()
returns text language sql stable security definer as $$
  select role from public.profiles where user_id = auth.uid();
$$;

-- --------------------------------------------------------------- customers
create table public.customers (
  id uuid primary key,
  name text not null default '',
  address text not null default '',
  job_title text not null default '',
  duration_label text not null default '',
  sort_order int not null default 0,
  day_of_week text not null default '',
  mower text not null default '',
  details text not null default '',
  phone text not null default '',
  email text not null default '',
  height text not null default '',
  latitude double precision,
  longitude double precision,
  geocode_status text not null default '',
  visit_interval_weeks int not null default 1,
  default_rate numeric not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create trigger customers_updated_at before update on public.customers
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------ service_items
create table public.service_items (
  id uuid primary key,
  customer_id uuid references public.customers (id) on delete cascade,
  name text not null default '',
  duration_minutes int not null default 15,
  interval_visits int not null default 2,
  sort_order int not null default 0,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create trigger service_items_updated_at before update on public.service_items
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------- job_types
create table public.job_types (
  id uuid primary key,
  name text not null default '',
  default_duration_minutes int not null default 30,
  is_default boolean not null default false,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create trigger job_types_updated_at before update on public.job_types
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------- work_records
create table public.work_records (
  id uuid primary key,
  customer_name text not null default '',
  address text not null default '',
  job_title text not null default '',
  phone text not null default '',
  notes text not null default '',
  scheduled_start timestamptz not null default now(),
  scheduled_end timestamptz not null default now(),
  actual_start timestamptz,
  actual_end timestamptz,
  status text not null default 'scheduled',
  planned_duration_minutes int,
  services_performed jsonb not null default '[]',
  extra_services jsonb not null default '[]',
  extra_notes text not null default '',
  invoice_number text,
  event_identifier text,
  latitude double precision,
  longitude double precision,
  assigned_to uuid references public.profiles (user_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index work_records_assigned_day on public.work_records (assigned_to, scheduled_start);
create trigger work_records_updated_at before update on public.work_records
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------- invoices
create table public.invoices (
  id uuid primary key,
  number text not null default '',
  customer_name text not null default '',
  customer_address text not null default '',
  issue_date timestamptz not null default now(),
  status text not null default 'open',
  notes text not null default '',
  lines jsonb not null default '[]',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create trigger invoices_updated_at before update on public.invoices
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------- mileage_entries
create table public.mileage_entries (
  id uuid primary key,
  date timestamptz not null default now(),
  from_label text not null default '',
  to_label text not null default '',
  miles numeric not null default 0,
  event_identifier text,
  user_id uuid references public.profiles (user_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create trigger mileage_entries_updated_at before update on public.mileage_entries
  for each row execute function public.set_updated_at();

-- -------------------------------------------------------------------- RLS
alter table public.profiles enable row level security;
alter table public.customers enable row level security;
alter table public.service_items enable row level security;
alter table public.job_types enable row level security;
alter table public.work_records enable row level security;
alter table public.invoices enable row level security;
alter table public.mileage_entries enable row level security;

-- Profiles: everyone signed in can read (names for pickers); only admin writes.
create policy profiles_read on public.profiles
  for select to authenticated using (true);
create policy profiles_admin_write on public.profiles
  for all to authenticated
  using (public.current_role() = 'admin')
  with check (public.current_role() = 'admin');

-- Managers/admins: full access to business tables.
create policy customers_mgr on public.customers
  for all to authenticated
  using (public.current_role() in ('admin', 'manager'))
  with check (public.current_role() in ('admin', 'manager'));
create policy service_items_mgr on public.service_items
  for all to authenticated
  using (public.current_role() in ('admin', 'manager'))
  with check (public.current_role() in ('admin', 'manager'));
create policy job_types_mgr on public.job_types
  for all to authenticated
  using (public.current_role() in ('admin', 'manager'))
  with check (public.current_role() in ('admin', 'manager'));
create policy work_records_mgr on public.work_records
  for all to authenticated
  using (public.current_role() in ('admin', 'manager'))
  with check (public.current_role() in ('admin', 'manager'));
create policy invoices_mgr on public.invoices
  for all to authenticated
  using (public.current_role() in ('admin', 'manager'))
  with check (public.current_role() in ('admin', 'manager'));
create policy mileage_mgr on public.mileage_entries
  for all to authenticated
  using (public.current_role() in ('admin', 'manager'))
  with check (public.current_role() in ('admin', 'manager'));

-- Crew: read the reference data they need in the field.
create policy customers_crew_read on public.customers
  for select to authenticated using (true);
create policy job_types_crew_read on public.job_types
  for select to authenticated using (true);
create policy service_items_crew_read on public.service_items
  for select to authenticated using (true);

-- Crew: see and update their own assigned jobs (completion data).
create policy work_records_crew_read on public.work_records
  for select to authenticated using (assigned_to = auth.uid());
create policy work_records_crew_update on public.work_records
  for update to authenticated
  using (assigned_to = auth.uid())
  with check (assigned_to = auth.uid());

-- Crew: log and read their own mileage.
create policy mileage_crew on public.mileage_entries
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
