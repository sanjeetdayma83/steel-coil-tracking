create extension if not exists pgcrypto;

create table if not exists public.locations (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  type text not null default 'Area',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.machines (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.lines (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  machine_id uuid not null references public.machines(id),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.ppc_plans (
  id uuid primary key default gen_random_uuid(),
  file_name text not null,
  imported_at timestamptz not null default now()
);

create table if not exists public.ppc_plan_rows (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.ppc_plans(id) on delete cascade,
  row_number integer not null,
  machine_code text not null,
  input_thickness numeric,
  input_width numeric,
  mother_coil text,
  slit_id text,
  production_order text,
  created_at timestamptz not null default now()
);

create index if not exists idx_ppc_plan_rows_machine
  on public.ppc_plan_rows(machine_code);

create table if not exists public.coils (
  id uuid primary key default gen_random_uuid(),
  material_code text not null,
  coil_no text not null unique,
  thickness numeric,
  width numeric,
  raw_qr text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.scan_sessions (
  id uuid primary key default gen_random_uuid(),
  location_id uuid not null references public.locations(id),
  machine_id uuid not null references public.machines(id),
  line_id uuid not null references public.lines(id),
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  scanned_by text
);

create table if not exists public.coil_scans (
  id uuid primary key default gen_random_uuid(),
  coil_id uuid not null references public.coils(id) on delete cascade,
  session_id uuid not null references public.scan_sessions(id) on delete cascade,
  location_id uuid not null references public.locations(id),
  machine_id uuid not null references public.machines(id),
  line_id uuid not null references public.lines(id),
  sequence_no integer not null,
  scanned_at timestamptz not null default now(),
  scanned_by text,
  unique(session_id, coil_id)
);

create index if not exists idx_coil_scans_location on public.coil_scans(location_id);
create index if not exists idx_coil_scans_machine on public.coil_scans(machine_id);
create index if not exists idx_coil_scans_coil on public.coil_scans(coil_id);

create table if not exists public.coil_location_history (
  id uuid primary key default gen_random_uuid(),
  coil_id uuid not null references public.coils(id) on delete cascade,
  scan_id uuid not null references public.coil_scans(id) on delete cascade,
  location_id uuid not null references public.locations(id),
  machine_id uuid not null references public.machines(id),
  line_id uuid not null references public.lines(id),
  sequence_no integer not null,
  scanned_at timestamptz not null default now(),
  scanned_by text
);

create index if not exists idx_coil_history_coil on public.coil_location_history(coil_id, scanned_at desc);
