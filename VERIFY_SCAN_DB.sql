-- STEEL COIL TRACKING - SCAN DB VERIFICATION
-- Run after at least one real QR scan.

select 'scan_sessions' as table_name, count(*) as row_count
from public.scan_sessions
union all
select 'coils', count(*) from public.coils
union all
select 'coil_scans', count(*) from public.coil_scans
union all
select 'coil_plan_links', count(*) from public.coil_plan_links;

select
  cs.id,
  cs.sequence_no,
  c.coil_no,
  c.material_code,
  c.thickness,
  c.width,
  l.name as location_name,
  ln.name as line_name,
  cs.operator_label,
  cs.scanned_at
from public.coil_scans cs
join public.coils c on c.id = cs.coil_id
join public.app_locations l on l.id = cs.location_id
join public.app_lines ln on ln.id = cs.line_id
order by cs.scanned_at desc
limit 20;

select
  upper(trim(coil_no)) as coil_no,
  count(*) as physical_rows
from public.coils
group by upper(trim(coil_no))
having count(*) > 1;
