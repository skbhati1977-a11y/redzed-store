-- TEST71 V632. Read-time projections only; no evidence-record repairs.
-- V628/V630/V631 are already applied and must not be replayed.
begin;

create or replace function public.rr_cutting_lot_assigned_v632(p_canonical_lot_id text)
returns boolean language sql stable set search_path='' as $function$
  select exists(
    select 1 from public.rr_upm_work_assignments_v8 a
    where a.canonical_lot_id=p_canonical_lot_id
      and upper(public.rr_upm_core_department_v9077(a.department_code))<>'CUTTING'
      and upper(coalesce(a.status,'')) not in('CANCELLED','CANCELED','VOID')
  )
$function$;
revoke all on function public.rr_cutting_lot_assigned_v632(text) from public,anon,authenticated;
grant execute on function public.rr_cutting_lot_assigned_v632(text) to service_role;

create or replace function public.rr_cutting_child_lifecycle_v628(p_cb_unit_id uuid)
returns jsonb language plpgsql stable security definer
set search_path='public'
as $function$
declare
  v_unit public.rr_cb_units%rowtype;
  v_decisions_complete boolean:=false;
  v_due_count integer:=0;
  v_lots jsonb:='[]'::jsonb;
  v_state text;
  v_production_assigned boolean:=false;
begin
  select * into v_unit from public.rr_cb_units where id=p_cb_unit_id;
  if not found or not coalesce(v_unit.is_final,true) or not coalesce(v_unit.is_cutting_enabled,true) then
    return jsonb_build_object('cb_unit_id',p_cb_unit_id,'state','NOT_AVAILABLE',
      'canonical_state','CLOSE','all_decisions_complete',false,'material_due_count',0,
      'production_assigned',false,'lots','[]'::jsonb);
  end if;

  select coalesce(d.all_decisions_complete,false) into v_decisions_complete
  from public.rr_pm_decision_status_v802 d where d.cb_unit_id=p_cb_unit_id;

  select count(*)::integer into v_due_count
  from public.rr_cb_purchase_entries e
  where e.cb_id=v_unit.purchase_id and upper(coalesce(e.requirement_state,''))='DUE';

  select coalesce(jsonb_agg(jsonb_build_object('lot_no',x.lot_no,'cutting_pieces',x.pcs,'source',x.source)
    order by x.lot_no),'[]'::jsonb) into v_lots
  from (
    select distinct on (lot_no) lot_no,pcs,source
    from (
      select upper(btrim(l.lot_no)) lot_no,
        coalesce(nullif(l.actual_pcs,0),nullif(l.planned_pcs,0),0)::numeric pcs,
        'rr_cutting_lots_v3'::text source,1 priority
      from public.rr_cutting_lots_v3 l
      where l.cb_unit_id=p_cb_unit_id
        and upper(coalesce(l.status,'')) not in('CANCELLED','CANCELED')
      union all
      select upper(btrim(l.lot_no)),
        coalesce(nullif(l.actual_pcs,0),nullif(l.planned_pcs,0),0)::numeric,
        'rr_production_lots'::text,2
      from public.rr_production_lots l
      where l.cb_unit_id=p_cb_unit_id
        and upper(coalesce(l.status,'')) not in('CANCELLED','CANCELED')
      union all
      select upper(btrim(l.lot_no)),
        coalesce(nullif(l.verified_cut_qty,0),nullif(l.original_cut_qty,0),nullif(l.total_qty,0),0)::numeric,
        'rr_upm_lot_registry'::text,3
      from public.rr_upm_lot_registry l
      where upper(coalesce(l.cb_no,''))=upper(v_unit.cb_code)
         or l.metadata->>'cb_unit_id'=p_cb_unit_id::text
    ) s
    order by lot_no,priority
  ) x;

  v_state:=case
    when jsonb_array_length(v_lots)>0 then 'RELEASED'
    when not coalesce(v_decisions_complete,false) then 'ART_DUE'
    when v_due_count>0 then 'CUTTING_HOLD'
    else 'READY_FOR_CUTTING'
  end;

  -- Evaluate every released Lot independently; one assigned sibling cannot close another.
  select coalesce(jsonb_agg(l || jsonb_build_object(
    'canonical_lot_id',r.canonical_lot_id,
    'production_assigned',coalesce(public.rr_cutting_lot_assigned_v632(r.canonical_lot_id),false)
  )),'[]'::jsonb) into v_lots
  from jsonb_array_elements(v_lots) l
  left join lateral (
    select canonical_lot_id from public.rr_upm_lot_registry
    where upper(trim(lot_no))=l->>'lot_no'
    order by updated_at desc nulls last limit 1
  ) r on true;
  select jsonb_array_length(v_lots)>0 and not exists(
    select 1 from jsonb_array_elements(v_lots) l
    where not coalesce((l->>'production_assigned')::boolean,false)
  ) into v_production_assigned;

  return jsonb_build_object(
    'cb_unit_id',v_unit.id,'purchase_id',v_unit.purchase_id,'cb_code',v_unit.cb_code,
    'state',v_state,
    'canonical_state',case
      when v_state='RELEASED' and not v_production_assigned then 'WORKING'
      when v_state='RELEASED' then 'CLOSE'
      when v_state='READY_FOR_CUTTING' then 'OPEN'
      else 'OPEN' end,
    'all_decisions_complete',v_decisions_complete,
    'material_due_count',v_due_count,
    'production_assigned',v_production_assigned,
    'lots',v_lots);
end
$function$;

revoke all on function public.rr_cutting_child_lifecycle_v628(uuid) from public,anon;
grant execute on function public.rr_cutting_child_lifecycle_v628(uuid) to authenticated,service_role;

create or replace function public.rr_cutting_child_lifecycle_v615(p_cb_unit_id uuid)
returns jsonb language sql stable security definer
set search_path='public'
as $function$
  select public.rr_cutting_child_lifecycle_v628(p_cb_unit_id)
$function$;

revoke all on function public.rr_cutting_child_lifecycle_v615(uuid) from public,anon;
grant execute on function public.rr_cutting_child_lifecycle_v615(uuid) to authenticated,service_role;

create or replace function public.rr_cutting_lifecycle_batch_v632(p_cb_unit_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path='' as $function$
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  perform public.rr_assert_active_user_v1();
  if public.rr_upm_effective_role_v200() not in('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','CUTTING_MASTER') then
    raise exception 'Cutting lifecycle requires department staff authority.';
  end if;
  if cardinality(p_cb_unit_ids)>500 then raise exception 'Maximum 500 children per batch.'; end if;
  return (select coalesce(jsonb_agg(public.rr_cutting_child_lifecycle_v628(id)),'[]'::jsonb)
    from (select distinct unnest(p_cb_unit_ids) id) u);
end
$function$;
revoke all on function public.rr_cutting_lifecycle_batch_v632(uuid[]) from public,anon;
grant execute on function public.rr_cutting_lifecycle_batch_v632(uuid[]) to authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rr_upm_ready_to_assign_v9107(p_canonical_lot_id text, p_department_code text, p_worker_id uuid, p_rows jsonb, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ctx jsonb:=public.rr_upm_effective_identity_v200();
  v_role text:=public.rr_upm_effective_role_v200();
  v_dept text:=public.rr_upm_core_department_v9077(p_department_code);v_lot_no text;v_worker_name text;v_worker_code text;
  v_row jsonb;v_colour text;v_qty numeric;v_due jsonb;v_match jsonb;v_sizes jsonb;v_count int:=0;v_total numeric:=0;
begin
  if auth.uid() is null then raise exception 'Login required.';end if;
  if not public.rr_upm_assignment_allowed_v200() then
    raise exception 'READY TO ASSIGN requires Line Man, Manager or Admin authority; effective role % is not allowed.',v_role;
  end if;
  if p_worker_id is null then raise exception 'Select worker.'; end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then raise exception 'Select at least one colour.'; end if;
  if public.rr_upm_worker_has_open_rectification_v9102(p_worker_id) then raise exception 'Worker has open RECTIFICATION. Finish it before new assignment.'; end if;
  select worker_name,worker_code into v_worker_name,v_worker_code from public.rr_upm_worker_list_v8_4(v_dept) where worker_id=p_worker_id limit 1;
  if v_worker_name is null then raise exception 'Selected worker is not active/mapped in %.',v_dept; end if;
  select lot_no into v_lot_no from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id limit 1;
  if v_lot_no is null then raise exception 'Lot not registered.'; end if;
  -- Serialize retries before taking the authoritative due snapshot.
  perform 1 from public.rr_upm_lot_registry
    where canonical_lot_id=p_canonical_lot_id for update;
  if (select count(*) from jsonb_array_elements(p_rows)) <>
     (select count(distinct upper(trim(x->>'colour_code'))) from jsonb_array_elements(p_rows) x) then
    raise exception 'Duplicate colour in assignment request.';
  end if;
  v_due:=public.rr_upm_department_colour_due_card_v9107(v_dept);
  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_colour:=upper(trim(v_row->>'colour_code'));
    select x into v_match from jsonb_array_elements(coalesce((select l->'assign_rows' from jsonb_array_elements(v_due->'lots') l where l->>'canonical_lot_id'=p_canonical_lot_id limit 1),'[]'::jsonb)) x where upper(x->>'colour_code')=v_colour limit 1;
    if v_match is null then raise exception 'Colour % is not currently READY TO ASSIGN in department %.',v_colour,v_dept; end if;
    v_qty:=coalesce((v_match->>'qty')::numeric,0);v_sizes:=coalesce(v_match->'size_breakup','[]'::jsonb);
    if v_qty<=0 then raise exception 'Colour % has no GOOD qty available.',v_colour; end if;
    if exists(select 1 from public.rr_upm_work_assignments_v8 a where a.canonical_lot_id=p_canonical_lot_id and upper(a.colour_code)=v_colour and a.status in('ASSIGNED','IN_PROGRESS')) then raise exception 'Colour % is already running.',v_colour; end if;
    if exists(select 1 from public.rr_upm_work_assignments_v8 a where a.canonical_lot_id=p_canonical_lot_id and upper(a.colour_code)=v_colour and public.rr_upm_core_department_v9077(a.department_code)=v_dept and a.status='COMPLETED') then raise exception 'Colour % already completed in %; normal reassignment blocked.',v_colour,v_dept; end if;
    insert into public.rr_upm_work_assignments_v8(canonical_lot_id,lot_no,department_code,colour_code,colour_name,worker_id,worker_code,worker_name_snapshot,assigned_qty,size_breakup,inbound_qty,inbound_breakup,status,source_type,assigned_by,assigned_by_name,remarks)
    values(p_canonical_lot_id,v_lot_no,v_dept,v_colour,v_colour,p_worker_id,v_worker_code,v_worker_name,ceil(v_qty)::int,v_sizes,v_qty,v_sizes,'ASSIGNED','GOOD_TRAVEL',auth.uid(),coalesce(v_ctx->>'display_name',auth.uid()::text),p_remarks);
    v_count:=v_count+1;v_total:=v_total+v_qty;
  end loop;
  return jsonb_build_object('ok',true,'version','V200_CANONICAL_ASSIGN_AUTHORITY','lot_no',v_lot_no,'department_code',v_dept,'worker_id',p_worker_id,'worker_name',v_worker_name,'colours_assigned',v_count,'qty_assigned',v_total,'effective_role',v_role);
end
$function$

;

create or replace function public.rr_real_chat_work_search_v317(
  p_status text default 'WORKING', p_search text default null,
  p_department_code text default null,p_limit integer default 500
) returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare
  b jsonb; cards jsonb; counts jsonb; r record; life jsonb; actions jsonb;
  want text:=upper(coalesce(p_status,'WORKING'));
  dept text:=upper(nullif(trim(p_department_code),''));
  role_code text; state text; cap integer:=least(greatest(coalesce(p_limit,500),1),500);
begin
  -- Existing authority, production routing, Fabrication mirror, receipts and privacy remain canonical.
  b:=public.rr_real_chat_work_search_v317_core_v401(p_status,p_search,p_department_code,p_limit);
  role_code:=upper(coalesce(b#>>'{actor,role}',b#>>'{actor,role_code}',''));
  select coalesce(jsonb_agg(c),'[]'::jsonb) into cards
  from jsonb_array_elements(coalesce(b->'cards','[]'::jsonb)) x(c)
  where not coalesce((upper(coalesce(c->>'department_code',''))='CUTTING' and (
    c->>'source_event_type' in('READY_FOR_CUTTING','CUTTING_RELEASE_SUCCEEDED','CUTTING_RELEASED_PENDING_ASSIGNMENT')
    or c->>'card_type' in('READY_FOR_CUTTING','CUTTING_RELEASED')
    or c->>'event_key' like 'CUTTING_ASSIGN:%'
    or c->>'event_key' like 'CUTTING_READY:%'
    or (c->>'source_module'='CUTTING' and c->>'work_category'='READY_TO_ASSIGN')
  )),false);

  if role_code in('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','CUTTING_MASTER')
     and (dept is null or dept='CUTTING') then
    if want='OPEN' then
      for r in
        select u.id,u.cb_code,u.cb_base_no,u.created_at
        from public.rr_cb_units u
        where coalesce(u.is_final,true) and coalesce(u.is_cutting_enabled,true)
          and (coalesce(trim(p_search),'')='' or lower(concat_ws(' ',u.cb_code,u.cb_base_no)) like '%'||lower(trim(p_search))||'%')
          and exists(select 1 from public.rr_pm_decision_status_v802 d where d.cb_unit_id=u.id and d.all_decisions_complete)
          and not exists(select 1 from public.rr_cutting_lots_v3 l where l.cb_unit_id=u.id and upper(coalesce(l.status,'')) not in('CANCELLED','CANCELED'))
          and not exists(select 1 from public.rr_production_lots l where l.cb_unit_id=u.id and upper(coalesce(l.status,'')) not in('CANCELLED','CANCELED'))
        order by u.created_at desc
      loop
        exit when jsonb_array_length(cards)>=cap;
        life:=public.rr_cutting_child_lifecycle_v628(r.id);
        continue when life->>'state'<>'READY_FOR_CUTTING';
        actions:=jsonb_build_array(
          jsonb_build_object('code','CUTTING_SINGLE_LOT','label','SINGLE LOT','href','real-cutting-master.html?cb_unit_id='||r.id||'&lot_mode=single','engine','EXISTING_CUTTING_RELEASE_CHAIN'),
          jsonb_build_object('code','CUTTING_MULTI_LOT','label','MULTI LOT','href','real-cutting-master.html?cb_unit_id='||r.id||'&lot_mode=multi','engine','EXISTING_CUTTING_RELEASE_CHAIN'));
        if role_code not in('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER') then actions:='[]'::jsonb; end if;
        cards:=cards||jsonb_build_array(jsonb_build_object(
          'event_key','CUTTING_READY:'||r.id,'cb_unit_id',r.id,'cb_no',r.cb_base_no,'cb_code',r.cb_code,
          'canonical_lot_id',null,'lot_no',null,'card_type','READY_FOR_CUTTING',
          'source_module','CUTTING','source_event_type','READY_FOR_CUTTING',
          'department_code','CUTTING','department_name','Cutting',
          'chat_status','OPEN','canonical_state','OPEN','source_status','OPEN',
          'message','Art / Print decision complete · Lot release pending',
          'actions',actions,'requires_action',jsonb_array_length(actions)>0,'event_at',r.created_at));
      end loop;
    elsif want in('WORKING','CLOSE') then
      for r in
        select distinct on(l.canonical_lot_id) l.*,
          public.rr_cutting_lot_assigned_v632(l.canonical_lot_id) assigned
        from public.rr_upm_lot_registry l
        where upper(coalesce(l.source_table,'')) in('RR_CUTTING_LOTS_V3','RR_PRODUCTION_LOTS')
          and (exists(select 1 from public.rr_cutting_lots_v3 c where upper(trim(c.lot_no))=upper(trim(l.lot_no)) and upper(coalesce(c.status,'')) not in('CANCELLED','CANCELED'))
            or exists(select 1 from public.rr_production_lots c where upper(trim(c.lot_no))=upper(trim(l.lot_no)) and upper(coalesce(c.status,'')) not in('CANCELLED','CANCELED')))
          and (coalesce(trim(p_search),'')='' or lower(concat_ws(' ',l.lot_no,l.cb_no,l.art_no)) like '%'||lower(trim(p_search))||'%')
        order by l.canonical_lot_id,l.updated_at desc nulls last
      loop
        state:=case when r.assigned then 'CLOSE' else 'WORKING' end;
        continue when state<>want;
        exit when jsonb_array_length(cards)>=cap;
        actions:=case when r.assigned or not public.rr_upm_assignment_allowed_v200() then '[]'::jsonb else
          jsonb_build_array(jsonb_build_object('code','ASSIGN_WORKER','label','ASSIGN WORK',
            'href','real-universal-production-v770-v9059.html?mode=TEST&rrMode=ASSIGN&lot='||r.lot_no,
            'engine','rr_upm_ready_to_assign_v9107')) end;
        cards:=cards||jsonb_build_array(jsonb_build_object(
          'event_key','CUTTING_ASSIGN:'||r.canonical_lot_id,'canonical_lot_id',r.canonical_lot_id,
          'lot_no',r.lot_no,'cb_no',r.cb_no,'art_no',r.art_no,'qty',coalesce(r.verified_cut_qty,r.original_cut_qty,r.total_qty,0),
          'card_type','CUTTING_RELEASED','source_module','CUTTING','source_event_type','CUTTING_RELEASE_SUCCEEDED',
          'department_code','CUTTING','department_name','Cutting','work_category','READY_TO_ASSIGN',
          'chat_status',state,'canonical_state',state,'source_status',state,'production_assigned',r.assigned,
          'message',case when r.assigned then 'Work assigned · Cutting handoff complete' else 'Lot released · Worker assignment pending' end,
          'actions',actions,'requires_action',jsonb_array_length(actions)>0,'read_only',r.assigned,'event_at',r.updated_at));
      end loop;
    end if;
  end if;
  select coalesce(jsonb_object_agg(d,n),'{}'::jsonb) into counts from(
    select coalesce(nullif(c->>'department_code',''),'UNKNOWN') d,count(*) n
    from jsonb_array_elements(cards) x(c) group by 1) q;
  return jsonb_set(jsonb_set(jsonb_set(b,'{cards}',cards,true),'{department_counts}',counts,true),'{version}','"V632_CANONICAL_CUTTING_HANDOFF"'::jsonb,true);
end
$function$;
revoke all on function public.rr_real_chat_work_search_v317(text,text,text,integer) from public,anon;
grant execute on function public.rr_real_chat_work_search_v317(text,text,text,integer) to authenticated,service_role;
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
    select count(*) into v_release_history_count
    from public.rr_real_chat_message_bridge_v70 b
    join public.rr_upm_lot_registry l on l.id::text=b.source_record_id
    where b.archived_at is null and b.source_module='CUTTING'
      and b.source_event_type='CUTTING_RELEASE_SUCCEEDED' and upper(l.lot_no)=upper(v_lot)
      and b.personal_payload->>'canonical_state'='WORKING';

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
revoke all on function public.rr_test_cutting_department_lifecycle_v632() from public,anon;
grant execute on function public.rr_test_cutting_department_lifecycle_v632() to authenticated,service_role;
notify pgrst,'reload schema';
CREATE OR REPLACE FUNCTION public.rr_real_chat_canonical_state_v83(p_source_module text, p_event_type text, p_action_code text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
with x as (
  select upper(coalesce(p_source_module,'')) m,upper(coalesce(p_event_type,'')) e,
    upper(coalesce(p_action_code,'')) a,
    upper(coalesce(p_payload->>'canonical_state',p_payload->>'chat_status',p_payload->>'message_status',p_payload->>'status','')) s
)
select case
  when m='CUTTING' and e='READY_FOR_CUTTING' then
    coalesce((select public.rr_cutting_child_lifecycle_v628(u.id)->>'canonical_state'
      from public.rr_cb_units u where u.id::text=p_payload->>'cb_unit_id' limit 1),'OPEN')
  when m='CUTTING' and e in('CUTTING_RELEASE_SUCCEEDED','CUTTING_RELEASED_PENDING_ASSIGNMENT') then
    coalesce((select case when public.rr_cutting_lot_assigned_v632(r.canonical_lot_id) then 'CLOSE' else 'WORKING' end
      from public.rr_upm_lot_registry r where r.canonical_lot_id=p_payload->>'canonical_lot_id'
        or upper(trim(r.lot_no))=upper(trim(p_payload->>'lot_no')) limit 1),'WORKING')
  when s in('OPEN','WORKING','CLOSE','REOPENED') then s
  when e='READY_FOR_CUTTING' then 'WORKING'
  when e='CUTTING_RELEASE_SUCCEEDED' then 'CLOSE'
  when e in('ART_DECIDE_PENDING','READY_TO_ASSIGN','LOT_OPEN','SALE_DRAFT','REQUIREMENT_OPEN','COLLECTION_OPEN') then 'OPEN'
  when e in('WORK_ASSIGNED','ALTER_FILL','LM_ACCEPT_REQUEST','LM_ACCEPT','REMAKE_ISSUE','RECEIVE_FROM_MASTER','DELIVER_TO_KARIGAR',
            'PACKING_ASSIGNED','PACKING_ACCEPTED','DESPATCH_IN_TRANSIT','SALE_CI_FINAL','DIFFERENCE_HOLD') then 'WORKING'
  when e in('ART_DECIDE_SUCCEEDED','ASSIGNMENT_COMPLETED','ASSIGNMENT_CANCELLED','WORK_SUBMITTED','KARIGAR_SUBMIT_GOOD',
            'RECEIVE_FROM_KARIGAR','DAMAGE_POSTED','RECTIFICATION_CLOSED','PACKING_SUBMITTED','DESPATCH_ACCEPTANCE_FINALIZED',
            'DESPATCH_RECEIVED','STOCK_POSTED','SALE_CANCELLED','SALE_QTY_VERIFIED','SALES_RETURN_POSTED','RCI_POSTED',
            'RCI_REVERSED','PAYMENT_POSTED','ORDER_CLOSED','COLLECTION_CLOSED') then 'CLOSE'
  when a in('ASSIGN_WORKER','PACKING_ASSIGN','PACKING_ACCEPT','OPEN_PI','FINALIZE_CI','STORE_RECEIVE','DIFFERENCE_HOLD_RESOLVE') then 'WORKING'
  when a in('SUBMIT','PACKING_SUBMIT','DESPATCH_CREATE','STOCK_POST','VERIFY_CPI_QTY','POST_SALES_RETURN','DAMAGE','RECEIVE_KARIGAR') then 'CLOSE'
  else 'WORKING'
end from x
$function$

;
commit;
