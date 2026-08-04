-- READ-ONLY verification after V766 install

select
  to_regprocedure('public.rr_upm_alter_stage_v740(text,text,text,jsonb,jsonb,boolean,uuid,text)') as live_wrapper,
  to_regprocedure('public.rr_upm_alter_stage_v740_core(text,text,text,jsonb,jsonb,boolean,uuid,text)') as preserved_responsibility_core;

-- Replace values below to check the Colour that showed the error.
-- This must return the original submitted worker with status COMPLETED when no active row exists.
select
  lot_no,
  department_code,
  colour_code,
  worker_id,
  worker_code,
  worker_name_snapshot,
  status,
  assigned_at,
  completed_at
from public.rr_upm_work_assignments_v8
where upper(department_code) = 'STICKER'
  and upper(colour_code) = 'C2'
order by coalesce(completed_at,updated_at,assigned_at) desc;

-- Current Lot LM enrolments; the active row should show Dhiraj for the relevant Lot.
select
  canonical_lot_id,
  lot_no,
  person_id,
  person_name_snapshot,
  worker_code_snapshot,
  department_code_snapshot,
  status,
  enrolled_at
from public.rr_upm_lot_role_enrolment_v740
where upper(role_code) = 'LINE_MAN'
order by enrolled_at desc
limit 50;

-- Responsibility engine remains stage based. Current holder is stored here.
select
  lot_no,
  origin_department_code,
  colour_code,
  size_code,
  open_qty,
  stage,
  responsible_id,
  responsible_name,
  responsible_role_code,
  responsible_department_code,
  updated_at
from public.rr_upm_alter_journey_v740
where stage not like 'CLOSED%'
order by updated_at desc
limit 100;
