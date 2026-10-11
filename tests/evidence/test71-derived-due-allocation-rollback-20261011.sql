BEGIN; SELECT set_config('request.jwt.claim.sub','af915a18-3823-48df-b039-1e4c7a88479b',true); DO $proof$
declare
  v_regular uuid;
  v_art uuid;
  v_cb_no text:='TEST71-V618-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  v_payload jsonb;
  v_action uuid:=gen_random_uuid();
  v_draft jsonb;
  v_retry jsonb;
  v_confirm jsonb;
  v_open jsonb;
  v_initial jsonb;
  v_mid jsonb;
  v_ready jsonb;
  v_units uuid[];
  v_bridge jsonb;
  v_result jsonb;
  v_residue integer;
begin
  perform public.rr_cb_department_assert_authority_v600();
  select id into v_regular from public.rr_material_categories
  where lower(category_code)='regular-cloth' and is_active limit 1;
  select id into v_art from public.rr_art_master where is_active order by created_at,id limit 1;
  if v_regular is null or v_art is null then
    raise exception 'V618 proof requires Regular Cloth and one active Art.';
  end if;

  begin
    v_payload:=jsonb_build_object(
      'cb_no',v_cb_no,'division_count',2,'colour_count',1,
      'remarks','TEST71 V618 rollback-only WORKING projection proof',
      'colours',jsonb_build_array(jsonb_build_object(
        'index',1,'name','Colour 1','image_url','https://example.invalid/test71-v618.jpg','confirmed',true
      )),
      'regular',jsonb_build_object(
        'client_key',gen_random_uuid(),'category_id',v_regular,
        'vendor','TEST71 Supplier','bill_no','TEST71-V618','bill_date',current_date,
        'fabric_name','TEST71 Regular Cloth','qty',120,'rate',365,'amount',43800,
        'rolls',jsonb_build_array(
          jsonb_build_object('colour_index',1,'roll_no',1,'qty',60),
          jsonb_build_object('colour_index',1,'roll_no',2,'qty',60)
        )
      ),
      'materials','[]'::jsonb
    );

    v_draft:=public.rr_cb_department_save_v600(null,v_action,false,v_payload);
    v_retry:=public.rr_cb_department_save_v600(null,v_action,false,v_payload);
    select value into v_open
    from jsonb_array_elements(public.rr_cb_department_cards_v600('OPEN',v_cb_no)->'cards')
    where value->>'cb_id'=v_draft->>'cb_id';

    v_confirm:=public.rr_cb_department_save_v600((v_draft->>'cb_id')::uuid,gen_random_uuid(),true,v_payload);
    select array_agg(id order by division_index) into v_units
    from public.rr_cb_units
    where purchase_id=(v_draft->>'cb_id')::uuid and coalesce(is_final,true);

    select value into v_initial
    from jsonb_array_elements(public.rr_cb_department_cards_v600('WORKING',v_cb_no)->'cards')
    where value->>'cb_id'=v_draft->>'cb_id';

    perform public.rr_pm_save_decision_bundle_v804(v_units[1],v_art,'NA','{}'::uuid[],'NA','{}'::uuid[],'NA','{}'::uuid[],'TEST');
    perform public.rr_pm_save_decision_bundle_v804(v_units[1],v_art,'NA','{}'::uuid[],'NA','{}'::uuid[],'NA','{}'::uuid[],'TEST');
    select value into v_mid
    from jsonb_array_elements(public.rr_cb_department_cards_v600('WORKING',v_cb_no)->'cards')
    where value->>'cb_id'=v_draft->>'cb_id';

    perform public.rr_pm_save_decision_bundle_v804(v_units[2],v_art,'NA','{}'::uuid[],'NA','{}'::uuid[],'NA','{}'::uuid[],'TEST');

    -- Required quantity comes from canonical Art/yield rules, not a guessed rate.
    if not exists(select 1 from public.rr_cb_purchase_entries where cb_id=(v_draft->>'cb_id')::uuid and entry_notes='AUTO ART COMBO MATERIAL' and requirement_state='DUE') then
      raise exception 'Fixture did not exercise derived DUE material';
    end if;
    if exists(
      select 1 from public.rr_cb_purchase_entries e
      where e.cb_id=(v_draft->>'cb_id')::uuid and e.entry_notes='AUTO ART COMBO MATERIAL' and e.requirement_state='DUE'
      and (e.quantity is distinct from (select sum(r.required_qty) from public.rr_cb_derived_requirement_v1 r where r.cb_id=e.cb_id and r.active and r.requirement_type='MATERIAL' and r.source_id=e.material_category_id)
        or (select count(*) from public.rr_cb_material_allocations a where a.purchase_entry_id=e.id) <> (select count(distinct r.cb_unit_id) from public.rr_cb_derived_requirement_v1 r where r.cb_id=e.cb_id and r.active and r.requirement_type='MATERIAL' and r.source_id=e.material_category_id and r.required_qty>0))
    ) then raise exception 'Derived quantity/allocation does not match canonical Art rules';end if;
    select jsonb_agg(jsonb_build_object('id',id,'quantity',quantity) order by id) into v_result from public.rr_cb_purchase_entries where cb_id=(v_draft->>'cb_id')::uuid and entry_notes='AUTO ART COMBO MATERIAL';
    perform public.rr_pm_save_decision_bundle_v804(v_units[2],v_art,'NA','{}'::uuid[],'NA','{}'::uuid[],'NA','{}'::uuid[],'TEST');
    if v_result is distinct from (select jsonb_agg(jsonb_build_object('id',id,'quantity',quantity) order by id) from public.rr_cb_purchase_entries where cb_id=(v_draft->>'cb_id')::uuid and entry_notes='AUTO ART COMBO MATERIAL') then raise exception 'Retry changed derived identity/quantity';end if;
    begin
      update public.rr_cb_purchase_entries set quantity=quantity+1 where cb_id=(v_draft->>'cb_id')::uuid and material_category_id=v_regular;
      raise exception 'Confirmed purchase mutation unexpectedly accepted';
    exception when others then
      if SQLERRM<>'CB, material, quantity or rate cannot change after division allocation' then raise;end if;
    end;
    select value into v_ready from jsonb_array_elements(public.rr_cb_department_cards_v600('CLOSE',v_cb_no)->'cards') where value->>'cb_id'=v_draft->>'cb_id';
    if v_ready->>'art_status'<>'COMPLETE' or coalesce((v_ready->>'cutting_ready_count')::int,0)<>0 then raise exception 'Unconfirmed derived material incorrectly released Cutting';end if;
    v_result:=jsonb_build_object('second_art_refresh','PASS','derived_quantity_and_allocation_match','PASS','retry_identity_and_quantity','PASS','confirmed_purchase_quantity_locked','PASS','unconfirmed_derived_material_holds_cutting','PASS');
    raise exception using errcode='P6181',message='TEST71_DERIVED_DUE_ROLLBACK';
  exception when sqlstate 'P6181' then
    if sqlerrm<>'TEST71_DERIVED_DUE_ROLLBACK' then raise;end if;
  end;
  select count(*) into v_residue from public.rr_fabric_purchases where cb_no=v_cb_no;
  if v_residue<>0 then raise exception 'Fixture residue';end if;
  perform set_config('test71.derived_due_proof', (v_result||jsonb_build_object('fixture_residue',v_residue))::text,true);
end;

$proof$; SELECT current_setting('test71.derived_due_proof')::jsonb AS result;ROLLBACK;
