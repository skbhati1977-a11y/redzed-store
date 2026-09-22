-- TEST71 V610: keep CB additional-material Unit selection canonical and make
-- generic Material creation serialize identical retries through the existing
-- Material Master engine. No named CB/Lot row is changed by this migration.
begin;

do $patch$
declare
  d text;
  old_sql text := $old$unit_code:=upper(coalesce(nullif(cat.unit,''),nullif(entry_row->>'unit','')));$old$;
  new_sql text := $new$unit_code:=public.rr_unit_require_code_v606(
      coalesce(nullif(entry_row->>'unit',''),nullif(cat.unit,''),'PCS')
    );$new$;
begin
  select pg_get_functiondef(
    'public.rr_cb_department_save_v600(uuid,uuid,boolean,jsonb)'::regprocedure
  ) into d;
  if position(new_sql in d)>0 then
    return;
  end if;
  if position(old_sql in d)=0 then
    raise exception 'V610 refused: canonical CB Unit assignment signature changed';
  end if;
  execute replace(d,old_sql,new_sql);
end
$patch$;

do $patch$
declare
  d text;
  anchor text := $old$v_norm:=public.rr_name_normalize_v805(v_name);
  select id into v_id from public.rr_material_master_v805$old$;
  replacement text := $new$v_norm:=public.rr_name_normalize_v805(v_name);
  -- Serialize identical create/retry requests before the existing lookup and
  -- unique index. The second request resolves to the same canonical row.
  perform pg_advisory_xact_lock(
    hashtextextended('RR_MATERIAL:'||v_type||':'||v_norm,610)
  );
  select id into v_id from public.rr_material_master_v805$new$;
begin
  select pg_get_functiondef(
    'public.rr_material_create_v805_31(text,text,text,text,text,numeric,text,numeric,text,numeric,text,uuid,jsonb)'::regprocedure
  ) into d;
  if position('RR_MATERIAL:' in d)>0 then
    return;
  end if;
  if position(anchor in d)=0 then
    raise exception 'V610 refused: canonical Material creator signature changed';
  end if;
  execute replace(d,anchor,replacement);
end
$patch$;

comment on function public.rr_cb_department_save_v600(uuid,uuid,boolean,jsonb) is
  'TEST71 canonical CB save V610: action-id idempotent; selected canonical additional-Material Unit persists; Regular Cloth stays KG; DUE Qty may remain NULL.';

comment on function public.rr_material_create_v805_31(text,text,text,text,text,numeric,text,numeric,text,numeric,text,uuid,jsonb) is
  'TEST71 canonical Material creator V610: OWNER/SUPER_ADMIN guarded; identical create/retry serialized and resolves one Material identity.';

create or replace function public.rr_test_cb_material_unit_v610()
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_regular uuid;
  v_additional uuid;
  v_cb_no text:='TEST71-V610-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  v_action uuid:=gen_random_uuid();
  v_payload jsonb;
  v_first jsonb;
  v_retry jsonb;
  v_detail jsonb;
  v_result jsonb;
  v_residue integer;
begin
  perform public.rr_cb_department_assert_authority_v600();
  select id into v_regular from public.rr_material_categories
  where lower(category_code)='regular-cloth' and is_active limit 1;
  select id into v_additional from public.rr_material_categories
  where is_active and id<>v_regular and not lower(coalesce(category_code,'')) like '%matching%'
    and public.rr_unit_resolve_code_v606(unit) is not null
    and public.rr_unit_require_code_v606(unit)<>'MTR'
  order by sort_order,category_name limit 1;
  if v_regular is null or v_additional is null then
    raise exception 'V610 proof requires Regular Cloth and one non-MTR Material mapping.';
  end if;

  begin
    v_payload:=jsonb_build_object(
      'cb_no',v_cb_no,'division_count',1,'colour_count',1,
      'remarks','TEST71 V610 rollback-only Material Unit proof',
      'colours',jsonb_build_array(jsonb_build_object(
        'index',1,'name','Colour 1','image_url','https://example.invalid/test71-v610.jpg','confirmed',true
      )),
      'regular',jsonb_build_object(
        'client_key',gen_random_uuid(),'category_id',v_regular,'vendor','TEST71 Supplier',
        'bill_no','TEST71-V610','bill_date',current_date,'fabric_name','TEST71 Regular Cloth',
        'qty',120,'rate',365,'amount',43800,
        'rolls',jsonb_build_array(jsonb_build_object('colour_index',1,'roll_no',1,'qty',120))
      ),
      'materials',jsonb_build_array(jsonb_build_object(
        'client_key',gen_random_uuid(),'category_id',v_additional,'state','DUE','unit','MTR',
        'cutting_blocking',false,'vendor','','bill_no','','bill_date','','fabric_name','',
        'qty','','rate',null,'amount',null
      ))
    );
    v_first:=public.rr_cb_department_save_v600(null,v_action,false,v_payload);
    v_retry:=public.rr_cb_department_save_v600(null,v_action,false,v_payload);
    v_detail:=public.rr_cb_department_detail_v600((v_first->>'cb_id')::uuid);
    v_result:=jsonb_build_object(
      'first',v_first,'retry',v_retry,
      'additional_unit',(select e->>'unit' from jsonb_array_elements(v_detail->'entries') e where e->>'entry_notes'='CB Material' limit 1),
      'additional_state',(select e->>'state' from jsonb_array_elements(v_detail->'entries') e where e->>'entry_notes'='CB Material' limit 1),
      'additional_qty',(select e->'qty' from jsonb_array_elements(v_detail->'entries') e where e->>'entry_notes'='CB Material' limit 1),
      'same_action_audits',(select count(*) from public.rr_cb_department_audit_v600 where action_id=v_action)
    );
    raise exception using errcode='P6101',message='TEST71_CB_MATERIAL_UNIT_ROLLBACK';
  exception when sqlstate 'P6101' then
    if sqlerrm<>'TEST71_CB_MATERIAL_UNIT_ROLLBACK' then raise; end if;
  end;

  select count(*) into v_residue from public.rr_fabric_purchases where cb_no=v_cb_no;
  return v_result||jsonb_build_object(
    'exact_invariant',v_result->>'additional_unit'='MTR'
      and v_result->>'additional_state'='DUE'
      and v_result->'additional_qty'='null'::jsonb
      and coalesce((v_result->'retry'->>'duplicate_blocked')::boolean,false)
      and (v_result->>'same_action_audits')::integer=1,
    'rolled_back',v_residue=0,'fixture_residue',v_residue
  );
end
$function$;

revoke all on function public.rr_test_cb_material_unit_v610() from public,anon;
grant execute on function public.rr_test_cb_material_unit_v610() to authenticated,service_role;

comment on function public.rr_test_cb_material_unit_v610() is
  'Rollback-only TEST71 proof: selected CB Unit wins over category default, DUE Qty remains NULL, retry is single, residue is zero.';

notify pgrst,'reload schema';
commit;
