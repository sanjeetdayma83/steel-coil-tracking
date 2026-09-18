
-- ============================================================
-- STEEL COIL TRACKING SYSTEM
-- DEVELOPMENT DATABASE SCHEMA
-- Supabase / PostgreSQL
--
-- IMPORTANT:
-- The policies below are DEV/TEST policies only.
-- Before production deployment, add authentication and tighten RLS.
-- ============================================================

create extension if not exists pgcrypto;
create extension if not exists pg_trgm;

create table if not exists public.app_machines (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.app_locations (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  location_type text not null default 'area',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.app_lines (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  location_id uuid references public.app_locations(id) on delete set null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.coils (
  id uuid primary key default gen_random_uuid(),
  coil_no text not null unique,
  material_code text,
  thickness numeric(12,4),
  width numeric(12,4),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.ppc_plans (
  id uuid primary key default gen_random_uuid(),
  file_name text not null,
  imported_at timestamptz not null default now(),
  row_count integer not null default 0,
  is_active boolean not null default true
);

create table if not exists public.ppc_plan_rows (
  id bigserial primary key,
  plan_id uuid not null references public.ppc_plans(id) on delete cascade,
  planned_machine_code text not null,
  previous_stage_code text,
  input_thickness numeric(12,4),
  input_width numeric(12,4),
  mother_coil text,
  slit_id text,
  created_at timestamptz not null default now()
);

create index if not exists coils_coil_no_search_idx
  on public.coils using gin (coil_no gin_trgm_ops);

create index if not exists ppc_plan_rows_machine_idx
  on public.ppc_plan_rows(planned_machine_code);

create index if not exists ppc_plan_rows_mother_coil_idx
  on public.ppc_plan_rows(mother_coil);

create table if not exists public.scan_sessions (
  id uuid primary key default gen_random_uuid(),
  location_id uuid not null references public.app_locations(id),
  line_id uuid not null references public.app_lines(id),
  operator_label text not null default 'Operator',
  started_at timestamptz not null default now(),
  ended_at timestamptz
);

create table if not exists public.coil_scans (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.scan_sessions(id) on delete cascade,
  coil_id uuid not null references public.coils(id),
  location_id uuid not null references public.app_locations(id),
  line_id uuid not null references public.app_lines(id),
  sequence_no integer not null,
  scanned_at timestamptz not null default now(),
  operator_label text not null default 'Operator',
  unique(session_id, coil_id)
);

create index if not exists coil_scans_coil_idx
  on public.coil_scans(coil_id, scanned_at desc);

create index if not exists coil_scans_location_line_idx
  on public.coil_scans(location_id, line_id, scanned_at desc);

-- Optional bridge for the later step where a QR coil number
-- can be reliably linked to an exact PPC plan row.
create table if not exists public.coil_plan_links (
  coil_id uuid primary key references public.coils(id) on delete cascade,
  ppc_plan_row_id bigint not null references public.ppc_plan_rows(id) on delete cascade,
  linked_at timestamptz not null default now(),
  linked_by text not null default 'system'
);

create or replace view public.v_current_coil_locations as
select distinct on (cs.coil_id)
  cs.coil_id,
  c.coil_no,
  c.material_code,
  c.thickness,
  c.width,
  cs.location_id,
  l.code as location_code,
  l.name as location_name,
  cs.line_id,
  ln.code as line_code,
  ln.name as line_name,
  cs.sequence_no,
  cs.scanned_at,
  cs.operator_label,
  cs.session_id
from public.coil_scans cs
join public.coils c on c.id = cs.coil_id
join public.app_locations l on l.id = cs.location_id
join public.app_lines ln on ln.id = cs.line_id
order by cs.coil_id, cs.scanned_at desc, cs.id desc;

-- Atomically assigns the next sequence for a location + line + day.
create or replace function public.record_coil_scan(
  p_session_id uuid,
  p_coil_no text,
  p_material_code text,
  p_thickness numeric,
  p_width numeric,
  p_location_id uuid,
  p_line_id uuid,
  p_operator_label text default 'Operator'
)
returns table (
  scan_id uuid,
  coil_id uuid,
  sequence_no integer,
  scanned_at timestamptz,
  is_duplicate boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_coil_id uuid;
  v_scan_id uuid;
  v_seq integer;
  v_scanned_at timestamptz := now();
  v_lock_key bigint;
begin
  -- Duplicate inside the same scan session.
  select cs.id, cs.coil_id, cs.sequence_no, cs.scanned_at
    into v_scan_id, v_coil_id, v_seq, v_scanned_at
  from public.coil_scans cs
  where cs.session_id = p_session_id
    and cs.coil_id = (select id from public.coils where coil_no = trim(p_coil_no))
  limit 1;

  if v_scan_id is not null then
    scan_id := v_scan_id;
    coil_id := v_coil_id;
    sequence_no := v_seq;
    scanned_at := v_scanned_at;
    is_duplicate := true;
    return next;
    return;
  end if;

  insert into public.coils(coil_no, material_code, thickness, width, updated_at)
  values (
    trim(p_coil_no),
    nullif(trim(p_material_code), ''),
    p_thickness,
    p_width,
    now()
  )
  on conflict (coil_no) do update
    set material_code = excluded.material_code,
        thickness = excluded.thickness,
        width = excluded.width,
        updated_at = now()
  returning id into v_coil_id;

  -- Stable signed bigint lock key from location + line + date.
  v_lock_key := hashtextextended(
    p_location_id::text || ':' ||
    p_line_id::text || ':' ||
    current_date::text,
    0
  );

  perform pg_advisory_xact_lock(v_lock_key);

  select coalesce(max(cs.sequence_no), 0) + 1
    into v_seq
  from public.coil_scans cs
  where cs.location_id = p_location_id
    and cs.line_id = p_line_id
    and cs.scanned_at::date = current_date;

  insert into public.coil_scans(
    session_id,
    coil_id,
    location_id,
    line_id,
    sequence_no,
    scanned_at,
    operator_label
  )
  values (
    p_session_id,
    v_coil_id,
    p_location_id,
    p_line_id,
    v_seq,
    v_scanned_at,
    coalesce(nullif(trim(p_operator_label), ''), 'Operator')
  )
  returning id into v_scan_id;

  scan_id := v_scan_id;
  coil_id := v_coil_id;
  sequence_no := v_seq;
  scanned_at := v_scanned_at;
  is_duplicate := false;
  return next;
end;
$$;

-- DEV-only: seed current machine codes found in the provided PPC file.
insert into public.app_machines(code, name)
values
  ('CRS00001', 'CRS00001'),
  ('CRS00002', 'CRS00002'),
  ('CRS00003', 'CRS00003'),
  ('CRS00004', 'CRS00004'),
  ('CRS00005', 'CRS00005'),
  ('CRS00006', 'CRS00006'),
  ('CRS00007', 'CRS00007'),
  ('CRS00008', 'CRS00008'),
  ('CRS00009', 'CRS00009'),
  ('CRS00010', 'CRS00010')
on conflict (code) do nothing;

-- ------------------------------------------------------------
-- RLS
-- DEV/TEST ONLY
-- ------------------------------------------------------------

alter table public.app_machines enable row level security;
alter table public.app_locations enable row level security;
alter table public.app_lines enable row level security;
alter table public.coils enable row level security;
alter table public.ppc_plans enable row level security;
alter table public.ppc_plan_rows enable row level security;
alter table public.scan_sessions enable row level security;
alter table public.coil_scans enable row level security;
alter table public.coil_plan_links enable row level security;

drop policy if exists dev_machines_all on public.app_machines;
create policy dev_machines_all on public.app_machines
for all to anon, authenticated using (true) with check (true);

drop policy if exists dev_locations_all on public.app_locations;
create policy dev_locations_all on public.app_locations
for all to anon, authenticated using (true) with check (true);

drop policy if exists dev_lines_all on public.app_lines;
create policy dev_lines_all on public.app_lines
for all to anon, authenticated using (true) with check (true);

drop policy if exists dev_coils_all on public.coils;
create policy dev_coils_all on public.coils
for all to anon, authenticated using (true) with check (true);

drop policy if exists dev_ppc_plans_all on public.ppc_plans;
create policy dev_ppc_plans_all on public.ppc_plans
for all to anon, authenticated using (true) with check (true);

drop policy if exists dev_ppc_plan_rows_all on public.ppc_plan_rows;
create policy dev_ppc_plan_rows_all on public.ppc_plan_rows
for all to anon, authenticated using (true) with check (true);

drop policy if exists dev_scan_sessions_all on public.scan_sessions;
create policy dev_scan_sessions_all on public.scan_sessions
for all to anon, authenticated using (true) with check (true);

drop policy if exists dev_coil_scans_all on public.coil_scans;
create policy dev_coil_scans_all on public.coil_scans
for all to anon, authenticated using (true) with check (true);

drop policy if exists dev_coil_plan_links_all on public.coil_plan_links;
create policy dev_coil_plan_links_all on public.coil_plan_links
for all to anon, authenticated using (true) with check (true);

grant select, insert, update, delete on all tables in schema public to anon, authenticated;
grant usage, select on all sequences in schema public to anon, authenticated;
grant execute on function public.record_coil_scan(uuid,text,text,numeric,numeric,uuid,uuid,text)
to anon, authenticated;

-- View access.
grant select on public.v_current_coil_locations to anon, authenticated;
