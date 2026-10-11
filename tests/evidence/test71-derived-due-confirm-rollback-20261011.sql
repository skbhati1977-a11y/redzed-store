BEGIN;SELECT set_config('request.jwt.claim.sub','af915a18-3823-48df-b039-1e4c7a88479b',true);DO $proof$
declare
  v_entry uuid; v_action uuid:=gen_random_uuid(); v_regular uuid;
  v_additional uuid;
  v_art uuid;
  v_cb_no text:='TEST71-V611-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  v_payload jsonb;
  v_draft jsonb;
  v_confirm jsonb;
  v_partial jsonb;
  v_retry jsonb;
  v_complete jsonb;
  v_partial_card jsonb;
  v_complete_card jsonb;
  v_cb uuid;
  v_unit uuid;
  v_result jsonb;
  v_residue integer;
begin
  perform public.rr_cb_department_assert_authority_v600();
  select id into v_regular from public.rr_material_categories
  where lower(category_code)='regular-cloth' and is_active limit 1;
  select id into v_additional from public.rr_material_categories
  where is_active and id<>v_regular and not lower(coalesce(category_code,'')) like '%matching%'
  order by sort_order,category_name limit 1;
  select id into v_art from public.rr_art_master where is_active order by created_at,id limit 1;
  if v_regular is null or v_additional is null or v_art is null then
    raise exception 'V611 proof requires Regular Cloth, one additional Material and one active Art.';
  end if;

  begin
    v_payload:=jsonb_build_object(
      'cb_no',v_cb_no,'division_count',1,'colour_count',1,
      'remarks','TEST71 V611 rollback-only WORKING Art proof',
      'colours',jsonb_build_array(jsonb_build_object(
        'index',1,'name','Colour 1',
        'image_url','https://example.invalid/test71-v611.jpg','confirmed',true
      )),
      'regular',jsonb_build_object(
        'client_key',gen_random_uuid(),'category_id',v_regular,
        'vendor','TEST71 Supplier','bill_no','TEST71-V611','bill_date',current_date,
        'fabric_name','TEST71 Regular Cloth','qty',120,'rate',365,'amount',43800,
        'rolls',jsonb_build_array(jsonb_build_object('colour_index',1,'roll_no',1,'qty',120))
      ),
      'materials','[]'::jsonb
    );
    v_draft:=public.rr_cb_department_save_v600(null,gen_random_uuid(),false,v_payload);
    v_cb:=(v_draft->>'cb_id')::uuid;
    v_confirm:=public.rr_cb_department_save_v600(v_cb,gen_random_uuid(),true,v_payload);
    select id into v_unit from public.rr_cb_units
    where purchase_id=v_cb and coalesce(is_final,true)
    order by division_index,id limit 1;

    perform public.rr_pm_save_decision_bundle_v804(v_unit,v_art,'NA','{}'::uuid[],'NA','{}'::uuid[],'NA','{}'::uuid[],'TEST');
    select id into v_entry from public.rr_cb_purchase_entries where cb_id=v_cb and requirement_state='DUE' and entry_notes='AUTO ART COMBO MATERIAL' limit 1;
    if v_entry is null then raise exception 'Derived DUE fixture missing';end if;
    select jsonb_agg(jsonb_build_object('id',e.id,'client_key',e.client_key,'category_id',e.material_category_id,'state','CONFIRMED','unit',e.unit,'vendor','TEST71 Supplier','bill_no','ROLLBACK-DERIVED-CONFIRM','bill_date',current_date,'fabric_name',e.fabric_name,'qty',e.quantity,'rate',1,'amount',e.quantity,'cutting_blocking',e.cutting_blocking)) into v_result from public.rr_cb_purchase_entries e where e.cb_id=v_cb and e.requirement_state='DUE';
    v_payload:=jsonb_set(v_payload,'{materials}',v_result);
    v_complete:=public.rr_cb_department_save_v600(v_cb,v_action,false,v_payload);
    if exists(select 1 from public.rr_cb_purchase_entries where cb_id=v_cb and requirement_state='DUE') then raise exception 'Canonical confirmation did not clear DUE';end if;
    v_retry:=public.rr_cb_department_save_v600(v_cb,v_action,false,v_payload);
    if not (v_retry->>'duplicate_blocked')::boolean then raise exception 'Confirmation retry duplicated';end if;
    if not exists(select 1 from public.rr_cb_purchase_entries where id=v_entry and requirement_state='CONFIRMED' and rate=1 and amount=quantity) then raise exception 'Confirmed actual quantity/rate/amount mismatch';end if;
    begin
      update public.rr_cb_purchase_entries set rate=2 where id=v_entry;
      raise exception 'Confirmed derived purchase rate mutation accepted';
    exception when others then if SQLERRM<>'CB, material, quantity or rate cannot change after division allocation' then raise;end if;end;
    v_result:=jsonb_build_object('canonical_derived_due_confirmation','PASS','confirmed_quantity_rate_amount','PASS','confirmation_retry','PASS','confirmed_derived_rate_locked','PASS');
    raise exception using errcode='P6111',message='TEST71_DERIVED_CONFIRM_ROLLBACK';
  exception when sqlstate 'P6111' then if sqlerrm<>'TEST71_DERIVED_CONFIRM_ROLLBACK' then raise;end if;end;
  select count(*) into v_residue from public.rr_fabric_purchases where cb_no=v_cb_no;
  if v_residue<>0 then raise exception 'Fixture residue';end if;
  perform set_config('test71.derived_confirm_proof',(v_result||jsonb_build_object('fixture_residue',v_residue))::text,true);
end;

$proof$;SELECT current_setting('test71.derived_confirm_proof')::jsonb AS result;ROLLBACK;
