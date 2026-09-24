-- V633: correct rollback proof to assert the authoritative read-time projection.
begin;
CREATE OR REPLACE FUNCTION public.rr_test_cutting_department_lifecycle_v632()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
 SET statement_timeout TO '45s'
AS $function$
declare
  v_profile record;
  v_regular uuid;
  v_additional uuid;
  v_art uuid;
  v_art_no text;
  v_cb_no text:='TEST71-V615-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  v_lot text:='T71C'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  v_additional_key uuid:=gen_random_uuid();
  v_payload jsonb;
  v_saved jsonb;
  v_cb uuid;
  v_unit uuid;
  v_colour uuid;
  v_art_due jsonb;
  v_hold jsonb;
  v_ready jsonb;
  v_close jsonb;
  v_request_1 jsonb;
  v_request_2 jsonb;
  v_decision_1 jsonb;
  v_decision_2 jsonb;
  v_release_id uuid;
  v_due_release_blocked boolean:=false;
  v_due_release_error text;
  v_retry_blocked boolean:=false;
  v_retry_error text;
  v_ready_bridge_count integer:=0;
  v_release_history_count integer:=0;
  v_request_status text;
  v_result jsonb;
  v_residue integer:=0;
  v_canonical text; v_dept text; v_candidate text; v_worker uuid; v_rows jsonb;
  v_due jsonb; v_lot_due jsonb; v_assigned_life jsonb; v_mirror jsonb;
  v_assign_retry_blocked boolean:=false; v_assignment_count integer;
begin
  perform set_config('statement_timeout','45000',true);

  select role_code,full_name into v_profile
  from public.rr_user_profiles
  where auth_user_id=auth.uid() and is_active
  order by updated_at desc nulls last limit 1;
  if lower(coalesce(v_profile.role_code,''))<>'super_admin'
     or lower(coalesce(v_profile.full_name,'')) not like '%test%e2e%' then
    raise exception 'TEST71 E2E Super Admin session required';
  end if;
  if coalesce((public.rr_upm_effective_identity_v200()->>'on_behalf')::boolean,false) then
    raise exception 'Return Act As to signed-in TEST E2E Super Admin before running fixture';
  end if;

  select id into v_regular from public.rr_material_categories
  where lower(category_code)='regular-cloth' and is_active limit 1;
  select id into v_additional from public.rr_material_categories
  where is_active and id<>v_regular and not lower(coalesce(category_code,'')) like '%matching%'
  order by sort_order,category_name limit 1;
  select id,art_no into v_art,v_art_no from public.rr_art_master
  where is_active order by created_at,id limit 1;
  if v_regular is null or v_additional is null or v_art is null then
    raise exception 'V615 proof requires Regular Cloth, one additional Material and one active Art';
  end if;

  begin
    v_payload:=jsonb_build_object(
      'cb_no',v_cb_no,'division_count',1,'colour_count',1,
      'remarks','TEST71 V615 rollback-only Cutting lifecycle proof',
      'colours',jsonb_build_array(jsonb_build_object(
        'index',1,'name','TEST COLOUR','image_url','https://example.invalid/test71-v615.jpg','confirmed',true
      )),
      'regular',jsonb_build_object(
        'client_key',gen_random_uuid(),'category_id',v_regular,
        'vendor','TEST71 Supplier','bill_no','TEST71-V615','bill_date',current_date,
        'fabric_name','TEST71 Regular Cloth','qty',1,'rate',1,'amount',1,
        'rolls',jsonb_build_array(jsonb_build_object('colour_index',1,'roll_no',1,'qty',1))
      ),
      'materials',jsonb_build_array(jsonb_build_object(
        'client_key',v_additional_key,'category_id',v_additional,
        'state','DUE','unit','PCS','cutting_blocking',true,
        'vendor','','bill_no','','bill_date','','fabric_name','','qty','','rate',null,'amount',null
      ))
    );

    v_saved:=public.rr_cb_department_save_v600(null,gen_random_uuid(),false,v_payload);
    v_cb:=(v_saved->>'cb_id')::uuid;
    perform public.rr_cb_department_save_v600(v_cb,gen_random_uuid(),true,v_payload);
    select id into v_unit from public.rr_cb_units
    where purchase_id=v_cb and coalesce(is_final,true)
    order by division_index,id limit 1;
    select id into v_colour from public.rr_cb_colours
    where cb_id=v_cb order by colour_order,id limit 1;

    perform public.rr_real_chat_reconcile_cb_children_v105();
    v_art_due:=public.rr_cutting_child_lifecycle_v615(v_unit);

    perform public.rr_pm_save_decision_bundle_v804(
      v_unit,v_art,'NA','{}'::uuid[],'NA','{}'::uuid[],'NA','{}'::uuid[],'TEST'
    );
    v_hold:=public.rr_cutting_child_lifecycle_v615(v_unit);

    begin
      perform public.rr_release_single_lot_v3(
        v_lot,v_unit,current_date,'TEST71 Cutting lifecycle',v_art_no,'N/A','TEST E2E',
        array['L']::text[],1,1,0,0,0,'small','half','without',0,
        'TEST71 V615 DUE gate attempt',jsonb_build_array(jsonb_build_object(
          'cb_colour_id',v_colour::text,'colour_name','TEST COLOUR','size_code','L','qty',1
        ))
      );
    exception when others then
      v_due_release_error:=sqlerrm;
      v_due_release_blocked:=sqlerrm ilike '%Material Due%';
    end;

    update public.rr_cb_purchase_entries
    set requirement_state='CONFIRMED',quantity=1,rate=1,
        vendor_name='TEST71 Supplier',vendor_bill_no='TEST71-V615-M',bill_date=current_date,
        fabric_name='TEST71 Confirmed Material'
    where cb_id=v_cb and client_key=v_additional_key;
    perform public.rr_real_chat_reconcile_cb_children_v105();
    v_ready:=public.rr_cutting_child_lifecycle_v615(v_unit);

    v_request_1:=public.rr_cutting_request_multi_art_decision_v1(v_unit);
    v_request_2:=public.rr_cutting_request_multi_art_decision_v1(v_unit);
    v_decision_1:=public.rr_cutting_decide_multi_art_v1(
      (v_request_1->>'request_id')::uuid,'SAME_EXISTING',2,'[]'::jsonb
    );
    v_decision_2:=public.rr_cutting_decide_multi_art_v1(
      (v_request_1->>'request_id')::uuid,'SAME_EXISTING',2,'[]'::jsonb
    );

    perform public.rr_save_cutting_lot_draft_v1(
      v_cb,v_unit,'single',v_lot,
      jsonb_build_object('source','TEST71_V615_ROLLBACK','lot_no',v_lot),
      'OPEN',null,null
    );
    v_release_id:=public.rr_release_single_lot_v3(
      v_lot,v_unit,current_date,'TEST71 Cutting lifecycle',v_art_no,'N/A','TEST E2E',
      array['L']::text[],1,1,0,0,0,'small','half','without',0,
      'TEST71 V615 rollback-only release',jsonb_build_array(jsonb_build_object(
        'cb_colour_id',v_colour::text,'colour_name','TEST COLOUR','size_code','L','qty',1
      ))
    );
    perform public.rr_real_chat_reconcile_cb_children_v105();
    v_close:=public.rr_cutting_child_lifecycle_v615(v_unit);

    select status into v_request_status
    from public.rr_cutting_multi_art_decisions_v1
    where id=(v_request_1->>'request_id')::uuid;
    select count(*) into v_ready_bridge_count
    from public.rr_real_chat_message_bridge_v70
    where archived_at is null and source_module='CUTTING'
      and source_event_type='READY_FOR_CUTTING' and source_record_id=v_unit::text;
    -- Read canonical state, not a historical bridge payload.
    select count(*) into v_release_history_count
    from jsonb_array_elements(public.rr_real_chat_work_search_v317('WORKING',v_lot,'CUTTING',100)->'cards') c
    where c->>'lot_no'=v_lot and c->>'canonical_state'='WORKING';

    begin
      perform public.rr_release_single_lot_v3(
        v_lot,v_unit,current_date,'TEST71 Cutting lifecycle',v_art_no,'N/A','TEST E2E',
        array['L']::text[],1,1,0,0,0,'small','half','without',0,
        'TEST71 V615 retry',jsonb_build_array(jsonb_build_object(
          'cb_colour_id',v_colour::text,'colour_name','TEST COLOUR','size_code','L','qty',1
        ))
      );
    exception when others then
      v_retry_error:=sqlerrm;
      v_retry_blocked:=sqlerrm ilike '%already%' or sqlstate='23505';
    end;

    v_result:=jsonb_build_object(
      'art_due',v_art_due,'cutting_hold',v_hold,'ready',v_ready,'close',v_close,
      'due_release_blocked',v_due_release_blocked,'due_release_error',v_due_release_error,
      'request_first',v_request_1,'request_retry',v_request_2,
      'decision_first',v_decision_1,'decision_retry',v_decision_2,
      'release_id',v_release_id,'release_retry_blocked',v_retry_blocked,'release_retry_error',v_retry_error,
      'multi_request_final_status',v_request_status,
      'actionable_ready_count',v_ready_bridge_count,'release_history_count',v_release_history_count
    );

    if v_art_due->>'state'<>'ART_DUE'
       or v_hold->>'state'<>'CUTTING_HOLD'
       or coalesce((v_hold->>'material_due_count')::integer,0)<>1
       or not v_due_release_blocked
       or v_ready->>'state'<>'READY_FOR_CUTTING'
       or v_ready->>'canonical_state'<>'OPEN'
       or v_request_1->>'request_id'<>v_request_2->>'request_id'
       or not coalesce((v_request_2->>'duplicate_blocked')::boolean,false)
       or not coalesce((v_decision_2->>'duplicate_blocked')::boolean,false)
       or v_close->>'state'<>'RELEASED'
       or v_close->>'canonical_state'<>'WORKING'
       or not v_retry_blocked
       or v_request_status<>'CONSUMED'
       or v_ready_bridge_count<>0
       or v_release_history_count<>1 then
      raise exception 'V615 Cutting lifecycle invariant failed: %',v_result;
    end if;

    select canonical_lot_id into v_canonical from public.rr_upm_lot_registry where lot_no=v_lot limit 1;
    v_mirror:=public.rr_real_chat_work_search_v317('OPEN',v_lot,'FABRICATION',100);
    if not exists(select 1 from jsonb_array_elements(v_mirror->'cards') c where c->>'canonical_lot_id'=v_canonical) then
      raise exception 'Released fixture missing from Fabrication OPEN: %',v_mirror;
    end if;
    foreach v_candidate in array array['PRINTING','STITCHING','OVERLOCK','THREAD_CUTTING','CHECKING','PRESS','FOLDING','PACKING'] loop
      v_due:=public.rr_upm_department_colour_due_card_v9107(v_candidate);
      select l into v_lot_due from jsonb_array_elements(coalesce(v_due->'lots','[]'::jsonb)) l
        where l->>'canonical_lot_id'=v_canonical and jsonb_array_length(coalesce(l->'assign_rows','[]'::jsonb))>0 limit 1;
      if v_lot_due is not null then
        select worker_id into v_worker from public.rr_upm_worker_list_v8_4(v_candidate)
          where not public.rr_upm_worker_has_open_rectification_v9102(worker_id) limit 1;
        if v_worker is not null then v_dept:=v_candidate; exit; end if;
      end if;
    end loop;
    if v_dept is null then raise exception 'No eligible worker/department for rollback assignment proof'; end if;
    v_rows:=v_lot_due->'assign_rows';
    perform public.rr_upm_ready_to_assign_v9107(v_canonical,v_dept,v_worker,v_rows,'TEST71 V632 rollback proof');
    v_assigned_life:=public.rr_cutting_child_lifecycle_v615(v_unit);
    if v_assigned_life->>'canonical_state'<>'CLOSE' then raise exception 'Assigned fixture must close Cutting: %',v_assigned_life; end if;
    if exists(select 1 from jsonb_array_elements(public.rr_real_chat_work_search_v317('WORKING',v_lot,'CUTTING',100)->'cards') c
      where c->>'canonical_lot_id'=v_canonical) then raise exception 'Assigned fixture still in Cutting WORKING'; end if;
    if not exists(select 1 from jsonb_array_elements(public.rr_real_chat_work_search_v317('CLOSE',v_lot,'CUTTING',100)->'cards') c
      where c->>'canonical_lot_id'=v_canonical and c->'actions'='[]'::jsonb and (c->>'read_only')::boolean) then
      raise exception 'Assigned fixture missing read-only Cutting CLOSE'; end if;
    begin
      perform public.rr_upm_ready_to_assign_v9107(v_canonical,v_dept,v_worker,v_rows,'TEST71 V632 duplicate retry');
    exception when others then
      v_assign_retry_blocked:=sqlerrm ilike '%READY TO ASSIGN%' or sqlerrm ilike '%already running%';
    end;
    select count(*) into v_assignment_count from public.rr_upm_work_assignments_v8 where canonical_lot_id=v_canonical;
    if not v_assign_retry_blocked or v_assignment_count<>jsonb_array_length(v_rows) then
      raise exception 'Duplicate assignment guard failed'; end if;
    v_result:=v_result||jsonb_build_object('released_working',v_close,'assigned_close',v_assigned_life,
      'fabrication_open_mirror',true,'assignment_retry_blocked',v_assign_retry_blocked,
      'assignment_count',v_assignment_count,'assignment_department',v_dept);

    raise exception using errcode='P6151',message='TEST71_CUTTING_LIFECYCLE_ROLLBACK';
  exception when sqlstate 'P6151' then
    if sqlerrm<>'TEST71_CUTTING_LIFECYCLE_ROLLBACK' then raise; end if;
  end;

  select
    (select count(*) from public.rr_fabric_purchases where cb_no=v_cb_no)
    +(select count(*) from public.rr_cb_units where id=v_unit)
    +(select count(*) from public.rr_cutting_lots_v3 where cb_unit_id=v_unit)
    +(select count(*) from public.rr_production_lots where cb_unit_id=v_unit)
    +(select count(*) from public.rr_cutting_multi_art_decisions_v1 where cb_unit_id=v_unit)
    +(select count(*) from public.rr_real_chat_message_bridge_v70
      where source_record_id=v_unit::text or personal_payload->>'cb_unit_id'=v_unit::text)
  into v_residue;

  return v_result||jsonb_build_object(
    'exact_invariant',true,'rolled_back',v_residue=0,'fixture_residue',v_residue
  );
end
$function$

;

commit;
