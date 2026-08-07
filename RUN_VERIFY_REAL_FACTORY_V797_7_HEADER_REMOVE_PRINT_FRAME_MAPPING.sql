-- REAL FACTORY V797.7
-- READ-ONLY VERIFY SQL
-- Verifies the Print No / Frame No identity resolver repair before HTML/JS release.
-- This script does not INSERT, UPDATE, DELETE, call the resolver, or change production data.

with
resolver_source as (
  select pg_get_functiondef(
    'public.rr_upm_resolve_identity_v740(text,boolean,text)'::regprocedure
  ) as function_definition
),
object_check as (
  select
    to_regprocedure('public.rr_upm_resolve_identity_v740(text,boolean,text)') is not null as identity_resolver_ok,
    to_regclass('public.rr_upm_lot_identity_lock_v740') is not null as identity_lock_table_ok,
    to_regclass('public.rr_upm_function_backup_v7977') is not null as backup_table_ok,
    has_function_privilege(
      'authenticated',
      'public.rr_upm_resolve_identity_v740(text,boolean,text)',
      'EXECUTE'
    ) as authenticated_execute_ok
),
patch_check as (
  select
    position('nullif(trim(coalesce(r.print_no,'''')),'''') is not null' in function_definition) > 0
      as print_required_gate_ok,
    position('nullif(trim(coalesce(r.frame_no,'''')),'''') is not null' in function_definition) > 0
      as frame_required_gate_ok,
    position('upper(trim(coalesce(r.print_no,''''))) not like ''%MAPPING REQUIRED%''' in function_definition) > 0
      as print_mapping_required_rejected,
    position('upper(trim(coalesce(r.frame_no,''''))) not like ''%MAPPING REQUIRED%''' in function_definition) > 0
      as frame_mapping_required_rejected
  from resolver_source
),
lock_check as (
  select
    count(*) as total_identity_locks,
    count(*) filter (
      where nullif(trim(coalesce(print_no,'')),'') is null
         or nullif(trim(coalesce(frame_no,'')),'') is null
         or upper(trim(coalesce(print_no,''))) like '%MAPPING REQUIRED%'
         or upper(trim(coalesce(frame_no,''))) like '%MAPPING REQUIRED%'
    ) as incomplete_identity_locks,
    count(*) filter (
      where nullif(trim(coalesce(print_no,'')),'') is not null
        and nullif(trim(coalesce(frame_no,'')),'') is not null
        and upper(trim(coalesce(print_no,''))) not like '%MAPPING REQUIRED%'
        and upper(trim(coalesce(frame_no,''))) not like '%MAPPING REQUIRED%'
    ) as complete_identity_locks
  from public.rr_upm_lot_identity_lock_v740
),
backup_check as (
  select count(*) as v7977_backup_rows
  from public.rr_upm_function_backup_v7977
  where function_identity='public.rr_upm_resolve_identity_v740(text,boolean,text)'
    and version_tag='PRE_V797_7_PRINT_FRAME_MAPPING'
    and nullif(trim(function_definition),'') is not null
),
preservation_check as (
  select
    to_regprocedure('public.rr_manual_rate_contact_payload_v797_6(uuid)') is not null
      as v7976_payload_function_ok,
    to_regprocedure('public.rr_mark_manual_contact_opened_v797_6(uuid,text)') is not null
      as v7976_opened_function_ok,
    to_regprocedure('public.rr_route_actual_rate_alert_v797_5(uuid)') is not null
      as v7976_alert_route_ok,
    to_regclass('public.rr_manual_contact_queue_v797_6') is not null
      as v7976_contact_queue_ok
),
result_check as (
  select
    o.*,
    p.*,
    l.*,
    b.*,
    v.*,
    (
      o.identity_resolver_ok
      and o.identity_lock_table_ok
      and o.backup_table_ok
      and o.authenticated_execute_ok
      and p.print_required_gate_ok
      and p.frame_required_gate_ok
      and p.print_mapping_required_rejected
      and p.frame_mapping_required_rejected
      and l.incomplete_identity_locks = 0
      and b.v7977_backup_rows >= 1
      and v.v7976_payload_function_ok
      and v.v7976_opened_function_ok
      and v.v7976_alert_route_ok
      and v.v7976_contact_queue_ok
    ) as overall_pass
  from object_check o
  cross join patch_check p
  cross join lock_check l
  cross join backup_check b
  cross join preservation_check v
)
select jsonb_build_object(
  'result',case when overall_pass then 'PASS' else 'CHECK_REQUIRED' end,
  'version','V797.7',
  'read_only',true,
  'identity_resolver',jsonb_build_object(
    'function_exists',identity_resolver_ok,
    'authenticated_execute',authenticated_execute_ok,
    'print_required_gate',print_required_gate_ok,
    'frame_required_gate',frame_required_gate_ok,
    'print_mapping_required_rejected',print_mapping_required_rejected,
    'frame_mapping_required_rejected',frame_mapping_required_rejected
  ),
  'identity_locks',jsonb_build_object(
    'total',total_identity_locks,
    'complete',complete_identity_locks,
    'incomplete',incomplete_identity_locks
  ),
  'safety',jsonb_build_object(
    'pre_patch_backup_rows',v7977_backup_rows,
    'production_quantity_mutation',false,
    'actual_rate_gate_changed',false,
    'v797_6_alert_flow_preserved',
      v7976_payload_function_ok
      and v7976_opened_function_ok
      and v7976_alert_route_ok
      and v7976_contact_queue_ok
  ),
  'header_removal_stage','COMBINED HTML + JS AFTER VERIFY PASS',
  'next',case
    when overall_pass then 'RELEASE COMBINED SQL + JS + HTML ZIP'
    else 'SEND THIS FULL RESULT FOR CORRECTION'
  end
) as real_factory_v797_7_verify_result
from result_check;
