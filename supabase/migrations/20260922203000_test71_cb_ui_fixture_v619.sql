-- TEST71 V619: uniquely addressable, reversible CB UI fixture.
-- The fixture exercises the canonical CB and Product Master writers. It is
-- restricted to the dedicated TEST71 E2E Super Admin and can delete only the
-- exact UUID-marked records it created.
begin;

create or replace function public.rr_test_cb_ui_fixture_v619(
  p_action text,
  p_fixture_key uuid
) returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_action text:=upper(trim(coalesce(p_action,'')));
  v_marker text;
  v_cb_no text;
  v_cb uuid;
  v_regular uuid;
  v_art uuid;
  v_units uuid[];
  v_assignments uuid[];
  v_payload jsonb;
  v_draft jsonb;
  v_confirm jsonb;
  v_profile public.rr_user_profiles%rowtype;
  v_residue integer:=0;
begin
  if p_fixture_key is null then raise exception 'Fixture key required.'; end if;
  select * into v_profile from public.rr_user_profiles
  where auth_user_id=auth.uid() and is_active and upper(coalesce(access_status,'ACTIVE'))='ACTIVE';
  if v_profile.id is null
    or v_profile.full_name<>'TEST71 E2E Super Admin'
    or upper(coalesce(v_profile.role_code,''))<>'SUPER_ADMIN' then
    raise exception 'Dedicated TEST71 E2E Super Admin required.' using errcode='42501';
  end if;
  if coalesce((public.rr_upm_effective_identity_v200()->>'on_behalf')::boolean,false) then
    raise exception 'Return Act As to signed-in TEST71 E2E Super Admin first.' using errcode='42501';
  end if;

  v_cb_no:='TEST71-UI-'||upper(substr(replace(p_fixture_key::text,'-',''),1,12));
  v_marker:='TEST71 V619 UI FIXTURE:'||p_fixture_key::text;
  select id into v_cb from public.rr_fabric_purchases where cb_no=v_cb_no;

  if v_action='CLEANUP' then
    if v_cb is null then
      return jsonb_build_object('ok',true,'cleaned',false,'fixture_residue',0,'cb_no',v_cb_no);
    end if;
    if not exists(select 1 from public.rr_fabric_purchases where id=v_cb and notes=v_marker) then
      raise exception 'V619 cleanup refused: fixture marker mismatch.' using errcode='42501';
    end if;
    select array_agg(id) into v_units from public.rr_cb_units where purchase_id=v_cb;
    select array_agg(id) into v_assignments from public.rr_cb_art_assignments where cb_id=any(coalesce(v_units,'{}'::uuid[]));

    delete from public.rr_real_chat_message_bridge_v70 b
    where b.source_record_id=v_cb::text
      or b.source_record_id=any(coalesce(v_units,'{}'::uuid[])::text[])
      or b.source_record_id=any(coalesce(v_assignments,'{}'::uuid[])::text[])
      or b.canonical_event_id in(
        select e.id from public.rr_real_chat_canonical_events_v96 e where e.parent_id=v_cb::text
      )
      or b.personal_payload->>'cb_id'=v_cb::text
      or b.group_payload->>'cb_id'=v_cb::text
      or b.personal_payload->>'cb_unit_id'=any(coalesce(v_units,'{}'::uuid[])::text[])
      or b.group_payload->>'cb_unit_id'=any(coalesce(v_units,'{}'::uuid[])::text[]);
    delete from public.rr_real_chat_canonical_events_v96 e
    where e.parent_id=v_cb::text
      or e.source_record_id=v_cb::text
      or e.source_record_id=any(coalesce(v_units,'{}'::uuid[])::text[])
      or e.source_record_id=any(coalesce(v_assignments,'{}'::uuid[])::text[]);
    delete from public.rr_cb_art_assignments where cb_id=any(coalesce(v_units,'{}'::uuid[]));
    delete from public.rr_cb_department_audit_v600 where cb_id=v_cb;
    delete from public.rr_cb_material_allocations
    where division_id=any(coalesce(v_units,'{}'::uuid[]))
      or purchase_entry_id in(select id from public.rr_cb_purchase_entries where cb_id=v_cb);
    delete from public.rr_cb_purchase_rolls where division_id=any(coalesce(v_units,'{}'::uuid[]));
    delete from public.rr_cb_units where purchase_id=v_cb;
    delete from public.rr_fabric_purchases where id=v_cb and notes=v_marker;

    select count(*) into v_residue from public.rr_fabric_purchases where cb_no=v_cb_no;
    return jsonb_build_object('ok',v_residue=0,'cleaned',true,'fixture_residue',v_residue,'cb_no',v_cb_no);
  end if;

  if v_action<>'SETUP' then raise exception 'Use SETUP or CLEANUP.'; end if;
  if v_cb is not null then
    if not exists(select 1 from public.rr_fabric_purchases where id=v_cb and notes=v_marker) then
      raise exception 'V619 setup refused: CB identity collision.' using errcode='23505';
    end if;
  else
    select id into v_regular from public.rr_material_categories
    where lower(category_code)='regular-cloth' and is_active limit 1;
    select id into v_art from public.rr_art_master where is_active order by created_at,id limit 1;
    if v_regular is null or v_art is null then raise exception 'V619 requires Regular Cloth and one active Art.'; end if;
    v_payload:=jsonb_build_object(
      'cb_no',v_cb_no,'division_count',2,'colour_count',1,'remarks',v_marker,
      'colours',jsonb_build_array(jsonb_build_object(
        'index',1,'name','TEST71 UI Colour','image_url','https://example.invalid/test71-v619.jpg','confirmed',true
      )),
      'regular',jsonb_build_object(
        'client_key',gen_random_uuid(),'category_id',v_regular,'vendor','TEST71 Supplier',
        'bill_no',v_cb_no,'bill_date',current_date,'fabric_name','TEST71 Regular Cloth',
        'qty',120,'rate',365,'amount',43800,
        'rolls',jsonb_build_array(jsonb_build_object('colour_index',1,'roll_no',1,'qty',120))
      ),
      'materials','[]'::jsonb
    );
    v_draft:=public.rr_cb_department_save_v600(null,p_fixture_key,false,v_payload);
    v_cb:=(v_draft->>'cb_id')::uuid;
    v_confirm:=public.rr_cb_department_save_v600(v_cb,gen_random_uuid(),true,v_payload);
    select array_agg(id order by division_index) into v_units
    from public.rr_cb_units where purchase_id=v_cb and coalesce(is_final,true);
    if coalesce(array_length(v_units,1),0)<>2 then raise exception 'V619 expected two canonical CB children.'; end if;
    perform public.rr_pm_save_decision_bundle_v804(
      v_units[2],v_art,'NA','{}'::uuid[],'NA','{}'::uuid[],'NA','{}'::uuid[],'TEST'
    );
  end if;

  select array_agg(id order by division_index) into v_units
  from public.rr_cb_units where purchase_id=v_cb and coalesce(is_final,true);
  return jsonb_build_object(
    'ok',true,'cb_id',v_cb,'cb_no',v_cb_no,'fixture_key',p_fixture_key,
    'art_due_unit_id',v_units[1],'ready_unit_id',v_units[2],
    'art_due_lifecycle',public.rr_cutting_child_lifecycle_v615(v_units[1]),
    'ready_lifecycle',public.rr_cutting_child_lifecycle_v615(v_units[2]),
    'fixture_rows',(select count(*) from public.rr_fabric_purchases where cb_no=v_cb_no)
  );
end
$function$;

revoke all on function public.rr_test_cb_ui_fixture_v619(text,uuid) from public,anon;
grant execute on function public.rr_test_cb_ui_fixture_v619(text,uuid) to authenticated,service_role;

comment on function public.rr_test_cb_ui_fixture_v619(text,uuid) is
  'Dedicated TEST71 E2E fixture: canonical two-child CB setup (one Art due, one Cutting ready), idempotent UUID namespace, and exact marker-guarded cleanup.';

notify pgrst,'reload schema';
commit;
