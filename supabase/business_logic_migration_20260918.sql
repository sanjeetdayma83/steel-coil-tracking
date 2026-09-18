-- ============================================================
-- STEEL COIL TRACKING V2
-- PHASE 1 DATABASE BUSINESS LOGIC
-- ============================================================

-- ------------------------------------------------------------
-- INDEXES
-- ------------------------------------------------------------

create index if not exists idx_ppc_plan_rows_plan_machine
  on public.ppc_plan_rows(plan_id, planned_machine_code);

create index if not exists idx_ppc_plan_rows_mother
  on public.ppc_plan_rows(mother_coil);

create index if not exists idx_ppc_plan_rows_slit
  on public.ppc_plan_rows(slit_id);

create index if not exists idx_coil_scans_session
  on public.coil_scans(session_id);

create index if not exists idx_coil_scans_coil
  on public.coil_scans(coil_id);

create index if not exists idx_coil_plan_links_coil
  on public.coil_plan_links(coil_id);

create index if not exists idx_coil_plan_links_plan_row
  on public.coil_plan_links(ppc_plan_row_id);


-- ------------------------------------------------------------
-- NORMALIZED PHYSICAL COIL NUMBER
--
-- Examples:
--
-- Mother = 26T120470
-- Slit   = C
-- Result = 26T120470C
--
-- Mother = 26T120470
-- Slit   = 26T120470C
-- Result = 26T120470C
-- ------------------------------------------------------------

create or replace function public.physical_coil_no(
  p_mother text,
  p_slit text
)
returns text
language plpgsql
immutable
as $function$
declare
  v_mother text := upper(trim(coalesce(p_mother, '')));
  v_slit text := upper(trim(coalesce(p_slit, '')));
begin

  if v_mother = '' and v_slit = '' then
    return null;
  end if;

  if v_mother = '' then
    return v_slit;
  end if;

  if v_slit = '' then
    return v_mother;
  end if;

  if v_slit like v_mother || '%' then
    return v_slit;
  end if;

  if v_mother like '%' || v_slit then
    return v_mother;
  end if;

  return v_mother || v_slit;
end;
$function$;


-- ------------------------------------------------------------
-- ACTIVE PPC VIEW
-- ONE ROW PER PPC PLANNING ROW
-- physical_coil_no is the deterministic QR/PPC key
-- ------------------------------------------------------------

create or replace view public.v_active_ppc_coils as
select
  p.id as plan_id,
  p.file_name,
  p.imported_at,
  r.id as plan_row_id,
  trim(r.planned_machine_code) as planned_machine_code,
  r.previous_stage_code,
  r.input_thickness,
  r.input_width,
  r.mother_coil,
  r.slit_id,
  public.physical_coil_no(
    r.mother_coil,
    r.slit_id
  ) as physical_coil_no
from public.ppc_plans p
join public.ppc_plan_rows r
  on r.plan_id = p.id
where p.is_active = true;


-- ------------------------------------------------------------
-- SYNC PPC PLAN -> PHYSICAL COIL LINKS
--
-- This does NOT delete PPC rows.
-- This does NOT delete coils.
-- This only establishes relationship records.
-- ------------------------------------------------------------

create or replace function public.sync_ppc_plan_links(
  p_plan_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_count integer := 0;
begin

  insert into public.coil_plan_links(
    coil_id,
    ppc_plan_row_id,
    linked_at,
    linked_by
  )
  select
    c.id,
    r.id,
    now(),
    'PPC_IMPORT'
  from public.ppc_plan_rows r
  join public.coils c
    on upper(trim(c.coil_no)) =
       public.physical_coil_no(r.mother_coil, r.slit_id)
  where r.plan_id = p_plan_id
  on conflict (coil_id, ppc_plan_row_id)
  do nothing;

  get diagnostics v_count = row_count;

  return v_count;
end;
$function$;


-- ------------------------------------------------------------
-- SAFE PPC PLAN ACTIVATION
--
-- New plan is created inactive.
-- Rows are imported.
-- Coils/links are synchronized.
-- Only then does this function switch active plan.
--
-- Old plan is NEVER deleted.
-- ------------------------------------------------------------

create or replace function public.activate_ppc_plan(
  p_plan_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
begin

  if not exists (
    select 1
    from public.ppc_plans
    where id = p_plan_id
  ) then
    raise exception 'PPC plan does not exist: %', p_plan_id;
  end if;

  update public.ppc_plans
  set is_active = false
  where is_active = true
    and id <> p_plan_id;

  update public.ppc_plans
  set is_active = true
  where id = p_plan_id;

end;
$function$;


-- ------------------------------------------------------------
-- DUPLICATE SAFETY FOR PPC LINKS
-- Derived links can safely be deduplicated.
-- PPC rows themselves are NEVER touched.
-- ------------------------------------------------------------

delete from public.coil_plan_links a
using public.coil_plan_links b
where a.id > b.id
  and a.coil_id = b.coil_id
  and a.ppc_plan_row_id = b.ppc_plan_row_id;


create unique index if not exists uq_coil_plan_links_pair
  on public.coil_plan_links(coil_id, ppc_plan_row_id);


-- ------------------------------------------------------------
-- SESSION SEQUENCE SAFETY
-- Every new scan session starts at 1.
-- ------------------------------------------------------------

delete from public.coil_scans a
using public.coil_scans b
where a.id > b.id
  and a.session_id = b.session_id
  and a.sequence_no = b.sequence_no;


create unique index if not exists uq_coil_scans_session_sequence
  on public.coil_scans(session_id, sequence_no);


-- ------------------------------------------------------------
-- MAIN SCAN RPC
-- ------------------------------------------------------------

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
returns table(
  scan_id uuid,
  coil_id uuid,
  sequence_no integer,
  scanned_at timestamptz,
  is_duplicate boolean
)
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_coil_id uuid;
  v_scan_id uuid;
  v_seq integer;
  v_scanned_at timestamptz := now();
  v_lock_key bigint;
begin

  p_coil_no := upper(trim(coalesce(p_coil_no, '')));
  p_material_code := trim(coalesce(p_material_code, ''));
  p_operator_label :=
    coalesce(nullif(trim(p_operator_label), ''), 'Operator');

  if p_coil_no = '' then
    raise exception 'Coil No cannot be empty';
  end if;

  -- ----------------------------------------------------------
  -- GET OR CREATE PHYSICAL COIL
  -- ----------------------------------------------------------

  insert into public.coils(
    coil_no,
    material_code,
    thickness,
    width,
    updated_at
  )
  values (
    p_coil_no,
    nullif(p_material_code, ''),
    p_thickness,
    p_width,
    now()
  )
  on conflict (coil_no)
  do update
  set
    material_code =
      coalesce(excluded.material_code, public.coils.material_code),
    thickness =
      coalesce(excluded.thickness, public.coils.thickness),
    width =
      coalesce(excluded.width, public.coils.width),
    updated_at = now()
  returning id into v_coil_id;


  -- ----------------------------------------------------------
  -- DUPLICATE WITHIN CURRENT SESSION
  -- ----------------------------------------------------------

  select
    cs.id,
    cs.sequence_no,
    cs.scanned_at
  into
    v_scan_id,
    v_seq,
    v_scanned_at
  from public.coil_scans cs
  where cs.session_id = p_session_id
    and cs.coil_id = v_coil_id
  order by cs.scanned_at
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


  -- ----------------------------------------------------------
  -- SESSION-LOCAL NUMBERING
  -- New session = 1.
  -- Location + Line changes create a new session in Flutter.
  -- Advisory lock prevents concurrent duplicate sequence.
  -- ----------------------------------------------------------

  v_lock_key :=
    hashtextextended(p_session_id::text, 0);

  perform pg_advisory_xact_lock(v_lock_key);

  select coalesce(max(cs.sequence_no), 0) + 1
  into v_seq
  from public.coil_scans cs
  where cs.session_id = p_session_id;


  -- ----------------------------------------------------------
  -- INSERT SCAN HISTORY
  -- ----------------------------------------------------------

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
    p_operator_label
  )
  returning id into v_scan_id;


  -- ----------------------------------------------------------
  -- AUTOMATIC ACTIVE PPC LINK
  --
  -- 26T120470 + C => 26T120470C
  -- ----------------------------------------------------------

  insert into public.coil_plan_links(
    coil_id,
    ppc_plan_row_id,
    linked_at,
    linked_by
  )
  select
    v_coil_id,
    r.id,
    now(),
    'SCAN'
  from public.ppc_plans p
  join public.ppc_plan_rows r
    on r.plan_id = p.id
  where p.is_active = true
    and public.physical_coil_no(
      r.mother_coil,
      r.slit_id
    ) = p_coil_no
  on conflict (coil_id, ppc_plan_row_id)
  do nothing;


  scan_id := v_scan_id;
  coil_id := v_coil_id;
  sequence_no := v_seq;
  scanned_at := v_scanned_at;
  is_duplicate := false;

  return next;

end;
$function$;


-- ------------------------------------------------------------
-- VERIFICATION VIEW
-- ------------------------------------------------------------

create or replace view public.v_active_ppc_coil_summary as
select
  physical_coil_no,
  array_agg(
    distinct planned_machine_code
    order by planned_machine_code
  ) as planned_machine_codes,
  count(*) as ppc_row_count
from public.v_active_ppc_coils
where physical_coil_no is not null
group by physical_coil_no;


-- ============================================================
-- END
-- ============================================================
