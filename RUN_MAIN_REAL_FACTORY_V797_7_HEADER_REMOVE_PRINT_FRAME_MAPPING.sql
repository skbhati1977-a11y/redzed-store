-- REAL FACTORY V797.7
-- MAIN: rebuild incomplete Print/Frame identity locks without touching production quantities.

begin;

create table if not exists public.rr_upm_function_backup_v7977 (
  id bigserial primary key,
  function_identity text not null,
  version_tag text not null,
  function_definition text not null,
  backed_up_at timestamptz not null default now()
);

insert into public.rr_upm_function_backup_v7977(
  function_identity, version_tag, function_definition
)
select
  'public.rr_upm_resolve_identity_v740(text,boolean,text)',
  'PRE_V797_7_PRINT_FRAME_MAPPING',
  pg_get_functiondef('public.rr_upm_resolve_identity_v740(text,boolean,text)'::regprocedure);

-- V761 already contains the full ordered mapping resolver. Its only remaining
-- fault is that an old lock was considered complete when CB + Art existed,
-- even if Print/Frame were blank. Patch that validity gate in the installed
-- function definition, preserving every existing resolver source and rule.
do $block$
declare
  v_def text;
  v_old text := $old$
      and nullif(trim(coalesce(r.art_no,'')),'') is not null
      and upper(trim(coalesce(r.cb_no,''))) <> 'MAPPING REQUIRED'
      and upper(trim(coalesce(r.art_no,''))) <> 'MAPPING REQUIRED';
$old$;
  v_new text := $new$
      and nullif(trim(coalesce(r.art_no,'')),'') is not null
      and nullif(trim(coalesce(r.print_no,'')),'') is not null
      and nullif(trim(coalesce(r.frame_no,'')),'') is not null
      and upper(trim(coalesce(r.cb_no,''))) <> 'MAPPING REQUIRED'
      and upper(trim(coalesce(r.art_no,''))) <> 'MAPPING REQUIRED'
      and upper(trim(coalesce(r.print_no,''))) not like '%MAPPING REQUIRED%'
      and upper(trim(coalesce(r.frame_no,''))) not like '%MAPPING REQUIRED%';
$new$;
begin
  v_def := pg_get_functiondef(
    'public.rr_upm_resolve_identity_v740(text,boolean,text)'::regprocedure
  );

  if position(v_old in v_def)=0 then
    raise exception 'V797.7 stopped safely: expected V761 identity validity gate was not found.';
  end if;

  v_def := replace(v_def,v_old,v_new);
  execute v_def;
end;
$block$;

-- Remove only incomplete cached identity locks. They are snapshots, not
-- production transactions. The resolver recreates them from Cutting/Registry/
-- Product/Print/Frame master sources on the next board or lot-form load.
delete from public.rr_upm_lot_identity_lock_v740
where nullif(trim(coalesce(print_no,'')),'') is null
   or nullif(trim(coalesce(frame_no,'')),'') is null
   or upper(trim(coalesce(print_no,''))) like '%MAPPING REQUIRED%'
   or upper(trim(coalesce(frame_no,''))) like '%MAPPING REQUIRED%';

grant execute on function public.rr_upm_resolve_identity_v740(text,boolean,text)
to authenticated;

commit;

select jsonb_build_object(
  'version','V797.7',
  'main_result','OK',
  'identity_resolver_patched',
    to_regprocedure('public.rr_upm_resolve_identity_v740(text,boolean,text)') is not null,
  'incomplete_identity_locks_remaining',(
    select count(*)
    from public.rr_upm_lot_identity_lock_v740
    where nullif(trim(coalesce(print_no,'')),'') is null
       or nullif(trim(coalesce(frame_no,'')),'') is null
       or upper(trim(coalesce(print_no,''))) like '%MAPPING REQUIRED%'
       or upper(trim(coalesce(frame_no,''))) like '%MAPPING REQUIRED%'
  ),
  'header_change','HTML stage after VERIFY PASS',
  'production_qty_changed',false,
  'actual_rate_gate_changed',false,
  'v797_6_alert_flow_changed',false
) as real_factory_v797_7_main_result;
