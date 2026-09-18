-- STEEL COIL TRACKING - SAFE PHYSICAL COIL + LIVE SEARCH PATCH
-- IMPORTANT:
--   * Does NOT delete or deduplicate ppc_plan_rows.
--   * ppc_plan_rows remain individual planning records.
--   * public.coils contains one physical Coil No.
-- The current DEV schema already has UNIQUE(coil_no), so no redundant
-- functional unique index is required.

create extension if not exists pg_trgm;

create index if not exists coils_coil_no_search_idx
  on public.coils using gin (coil_no gin_trgm_ops);

-- Seed one physical coil per normalized Mother Coil from the active plan.
-- In this project Mother Coil is the physical Coil No field available
-- in the current PPC schema.
insert into public.coils (coil_no, thickness, width)
select
  coil_no,
  input_thickness,
  input_width
from (
  select distinct on (upper(trim(mother_coil)))
    trim(mother_coil) as coil_no,
    input_thickness,
    input_width,
    id
  from public.ppc_plan_rows
  where nullif(trim(mother_coil), '') is not null
    and plan_id = (
      select id
      from public.ppc_plans
      where is_active = true
      order by imported_at desc
      limit 1
    )
  order by upper(trim(mother_coil)), id
) unique_coils
on conflict (coil_no) do update
set
  thickness = coalesce(public.coils.thickness, excluded.thickness),
  width = coalesce(public.coils.width, excluded.width),
  updated_at = now();

select
  count(*) as physical_coils,
  count(distinct upper(trim(coil_no))) as unique_coil_numbers
from public.coils;

select
  upper(trim(coil_no)) as coil_no,
  count(*) as rows
from public.coils
group by upper(trim(coil_no))
having count(*) > 1;
