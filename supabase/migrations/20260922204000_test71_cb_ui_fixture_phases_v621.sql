-- TEST71 V621: split the exact-marker V619 UI fixture into bounded,
-- phased canonical writes. This preserves production statement timeouts and
-- business semantics while avoiding a test-only multi-writer cold-path RPC.
begin;

do $patch$
declare
  d text;
  old_declarations text := $old$  v_payload jsonb;
  v_draft jsonb;
  v_confirm jsonb;$old$;
  new_declarations text := $new$  v_payload jsonb;
  v_confirm jsonb;$new$;
  old_action text := $old$  if v_action<>'SETUP' then raise exception 'Use SETUP or CLEANUP.'; end if;
  if v_cb is not null then
    if not exists(select 1 from public.rr_fabric_purchases where id=v_cb and notes=v_marker) then
      raise exception 'V619 setup refused: CB identity collision.' using errcode='23505';
    end if;
  else
    select id into v_regular from public.rr_material_categories
    where lower(category_code)='regular-cloth' and is_active limit 1;
    select id into v_art from public.rr_art_master where is_active order by created_at,id limit 1;
    if v_regular is null or v_art is null then raise exception 'V619 requires Regular Cloth and one active Art.'; end if;$old$;
  new_action text := $new$  if v_action not in('SETUP','READY') then raise exception 'Use SETUP, READY or CLEANUP.'; end if;
  if v_cb is not null then
    if not exists(select 1 from public.rr_fabric_purchases where id=v_cb and notes=v_marker) then
      raise exception 'V619 setup refused: CB identity collision.' using errcode='23505';
    end if;
  else
    if v_action='READY' then raise exception 'Run SETUP before READY.'; end if;
    select id into v_regular from public.rr_material_categories
    where lower(category_code)='regular-cloth' and is_active limit 1;
    if v_regular is null then raise exception 'V619 requires Regular Cloth.'; end if;$new$;
  old_writes text := $old$    v_draft:=public.rr_cb_department_save_v600(null,p_fixture_key,false,v_payload);
    v_cb:=(v_draft->>'cb_id')::uuid;
    v_confirm:=public.rr_cb_department_save_v600(v_cb,gen_random_uuid(),true,v_payload);
    select array_agg(id order by division_index) into v_units
    from public.rr_cb_units where purchase_id=v_cb and coalesce(is_final,true);
    if coalesce(array_length(v_units,1),0)<>2 then raise exception 'V619 expected two canonical CB children.'; end if;
    perform public.rr_pm_save_decision_bundle_v804(
      v_units[2],v_art,'NA','{}'::uuid[],'NA','{}'::uuid[],'NA','{}'::uuid[],'TEST'
    );
  end if;$old$;
  new_writes text := $new$    v_confirm:=public.rr_cb_department_save_v600(null,p_fixture_key,true,v_payload);
    v_cb:=(v_confirm->>'cb_id')::uuid;
    select array_agg(id order by division_index) into v_units
    from public.rr_cb_units where purchase_id=v_cb and coalesce(is_final,true);
    if coalesce(array_length(v_units,1),0)<>2 then raise exception 'V619 expected two canonical CB children.'; end if;
  end if;

  if v_action='READY' then
    select id into v_art from public.rr_art_master where is_active order by created_at,id limit 1;
    if v_art is null then raise exception 'V619 requires one active Art.'; end if;
    select array_agg(id order by division_index) into v_units
    from public.rr_cb_units where purchase_id=v_cb and coalesce(is_final,true);
    if coalesce(array_length(v_units,1),0)<>2 then raise exception 'V619 expected two canonical CB children.'; end if;
    perform public.rr_pm_save_decision_bundle_v804(
      v_units[2],v_art,'NA','{}'::uuid[],'NA','{}'::uuid[],'NA','{}'::uuid[],'TEST'
    );
  end if;$new$;
begin
  select replace(pg_get_functiondef(
    'public.rr_test_cb_ui_fixture_v619(text,uuid)'::regprocedure
  ),chr(13),'') into d;
  if position('phased canonical two-child' in coalesce(obj_description(
    'public.rr_test_cb_ui_fixture_v619(text,uuid)'::regprocedure,'pg_proc'
  ),''))>0 then return; end if;
  if position(old_declarations in d)=0 or position(old_action in d)=0 or position(old_writes in d)=0 then
    raise exception 'V621 refused: V619 fixture signature changed';
  end if;
  d:=replace(d,old_declarations,new_declarations);
  d:=replace(d,old_action,new_action);
  d:=replace(d,old_writes,new_writes);
  execute d;
  comment on function public.rr_test_cb_ui_fixture_v619(text,uuid) is
    'Dedicated TEST71 E2E fixture: phased canonical two-child CB setup/ready actions, idempotent UUID namespace, and exact marker-guarded cleanup.';
end
$patch$;

notify pgrst,'reload schema';
commit;
