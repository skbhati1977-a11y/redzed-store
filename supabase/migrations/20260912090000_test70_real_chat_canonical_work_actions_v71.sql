-- TEST70 Real Chat V71: canonical UPM queue projection and safe action links.
-- No production workflow engine is duplicated or replaced by this migration.
begin;

create or replace function public.rr_real_chat_work_inbox_v71(
  p_status text default 'WORKING',
  p_search text default null,
  p_department_code text default null,
  p_limit integer default 200
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_profile public.rr_user_profiles%rowtype;
  v_worker uuid;
  v_role text;
  v_home text;
  v_state text := upper(trim(coalesce(p_status,'WORKING')));
  v_find text := lower(trim(coalesce(p_search,'')));
  v_global boolean;
  v_staff boolean;
  v_department record;
  v_due jsonb;
  v_lot jsonb;
  v_row jsonb;
  v_assignment public.rr_upm_work_assignments_v8%rowtype;
  v_journey public.rr_upm_alter_journey_v740%rowtype;
  v_actions jsonb;
  v_cards jsonb := '[]'::jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_count integer := 0;
  v_cap integer := least(greatest(coalesce(p_limit,200),1),500);
  v_dept text;
  v_link text;
begin
  if v_uid is null then raise exception 'Login required.'; end if;
  perform public.rr_assert_active_user_v1();

  select * into v_profile
  from public.rr_user_profiles p
  where p.auth_user_id=v_uid and coalesce(p.is_active,false)
    and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
  order by p.updated_at desc nulls last limit 1;
  if not found then raise exception 'Active User Directory profile required.'; end if;

  if v_state not in ('OPEN','WORKING','CLOSE') then
    raise exception 'Status must be OPEN, WORKING or CLOSE.';
  end if;

  v_worker := public.rr_upm_current_worker_id_v9112();
  v_role := upper(replace(coalesce(v_profile.role_code,'WORKER'),' ','_'));
  v_home := public.rr_upm_core_department_v9077(v_profile.department_code);
  v_global := v_role in ('OWNER','SUPER_ADMIN','ADMIN');
  v_staff := v_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD','PRODUCTION','CUTTING_MASTER');
  if not v_staff and v_worker is null then raise exception 'Login is not linked to a Worker ID.'; end if;

  if v_state in ('OPEN','WORKING') then
    for v_department in
      select distinct m.department_code
      from public.rr_real_chat_department_membership_v70 m
      where m.is_active
        and (nullif(trim(p_department_code),'') is null
          or m.department_code=public.rr_upm_core_department_v9077(p_department_code))
        and (v_global or m.worker_id=v_worker or m.department_code=v_home)
        and exists (
          select 1 from public.rr_upm_departments d
          where public.rr_upm_core_department_v9077(d.department_code)=m.department_code
            and d.is_active
            and coalesce(d.colour_assignment_enabled,true)
            and coalesce(d.worker_assignment_enabled,true)
            and upper(coalesce(d.department_type,'PRODUCTION'))='PRODUCTION'
            and not coalesce(d.is_start_department,false)
            and not exists (
              select 1 from public.rr_upm_departments ch
              where ch.is_active
                and public.rr_upm_core_department_v9077(ch.parent_department_code)=m.department_code
            )
        )
      order by m.department_code
    loop
      v_dept := v_department.department_code;
      v_due := public.rr_upm_department_colour_due_card_v9109(v_dept);
      for v_lot in select value from jsonb_array_elements(coalesce(v_due->'lots','[]'::jsonb)) loop
        for v_row in select value from jsonb_array_elements(
          case when v_state='OPEN' then coalesce(v_lot->'assign_rows','[]'::jsonb)
               else coalesce(v_lot->'submit_rows','[]'::jsonb) end
        ) loop
          exit when v_count>=v_cap;
          if v_find<>'' and lower(concat_ws(' ',v_lot->>'lot_no',v_row->>'colour_code',v_dept,v_row->>'worker_first_name',v_state)) not like '%'||v_find||'%' then
            continue;
          end if;
          v_actions := '[]'::jsonb;
          v_link := 'real-universal-production-v770-v9059.html?mode=TEST&dept='||v_dept||'&from=TEST70_REAL_CHAT';

          if v_state='OPEN' then
            if v_role in ('ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD','CUTTING_MASTER') then
              v_actions := v_actions || jsonb_build_array(jsonb_build_object(
                'code','ASSIGN_WORKER','label','ASSIGN WORKER','href',v_link||'&rrMode=ASSIGN',
                'engine','rr_upm_ready_to_assign_v9107'));
            end if;
            v_cards := v_cards || jsonb_build_array(jsonb_build_object(
              'event_key','UPM_OPEN:'||(v_lot->>'canonical_lot_id')||':'||v_dept||':'||upper(v_row->>'colour_code'),
              'source_module','UNIVERSAL_PRODUCTION','canonical_lot_id',v_lot->>'canonical_lot_id',
              'lot_no',v_lot->>'lot_no','department_code',v_dept,'department_name',v_dept,
              'colour_code',upper(v_row->>'colour_code'),'colour_name',upper(v_row->>'colour_code'),
              'worker_id',null,'worker_name',null,'qty',coalesce((v_row->>'qty')::numeric,0),
              'actual_rate',null,'source_status','OPEN','chat_status','OPEN','event_at',v_row->>'due_since',
              'art_images',case when nullif(v_row->>'thumbnail_url','') is null then '[]'::jsonb else jsonb_build_array(v_row->>'thumbnail_url') end,
              'print_images','[]'::jsonb,'sticker_images','[]'::jsonb,'metal_id_images','[]'::jsonb,
              'actions',v_actions,'canonical_source','rr_upm_colour_queue_v741'));
          else
            select * into v_assignment from public.rr_upm_work_assignments_v8 a
            where a.id=(v_row->>'assignment_id')::uuid limit 1;
            if v_assignment.id is null then continue; end if;
            if not v_staff and v_assignment.worker_id is distinct from v_worker then continue; end if;

            if v_assignment.worker_id=v_worker or v_role in ('ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD') then
              v_actions := v_actions || jsonb_build_array(jsonb_build_object(
                'code','SUBMIT','label','SUBMIT','href',v_link||'&rrMode=SUBMIT&rrOpenSubmit='||v_assignment.canonical_lot_id,
                'engine','rr_upm_submit_colours_v741'));
            end if;
            if v_role in ('ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD') then
              v_actions := v_actions || jsonb_build_array(
                jsonb_build_object('code','ALTER_FILL','label','ALTER','href',v_link||'&rrMode=SUBMIT&rrOpenSubmit='||v_assignment.canonical_lot_id,'engine','rr_upm_alter_stage_v740'),
                jsonb_build_object('code','RECTIFICATION','label','RECTIFICATION','href',v_link||'&rrMode=SUBMIT&rrOpenSubmit='||v_assignment.canonical_lot_id,'engine','rr_upm_open_rectification_v9110'));
            end if;
            if coalesce(v_assignment.actual_rate,0)<=0 and v_role='MANAGER' then
              v_actions := v_actions || jsonb_build_array(jsonb_build_object(
                'code','DEPARTMENT_RATE','label','FILL DEPARTMENT RATE',
                'href','real-upm-costing-v9300.html?lot='||v_assignment.canonical_lot_id||'&dept='||v_dept,
                'engine','rr_upm_set_department_rate_v760'));
            end if;
            v_cards := v_cards || jsonb_build_array(jsonb_build_object(
              'event_key','UPM_ASSIGNMENT:'||v_assignment.id,'source_module','UNIVERSAL_PRODUCTION',
              'original_record_id',v_assignment.id,'canonical_lot_id',v_assignment.canonical_lot_id,
              'lot_no',v_assignment.lot_no,'department_code',v_dept,'department_name',v_dept,
              'colour_code',v_assignment.colour_code,'colour_name',v_assignment.colour_name,
              'worker_id',v_assignment.worker_id,'worker_name',v_assignment.worker_name_snapshot,
              'qty',greatest(coalesce(v_assignment.inbound_qty,0),coalesce(v_assignment.assigned_qty,0)),
              'actual_rate',v_assignment.actual_rate,'source_status',v_assignment.status,'chat_status','WORKING',
              'sender_user_id',v_assignment.assigned_by,'sender_name',v_assignment.assigned_by_name,
              'event_at',v_assignment.assigned_at,'art_images','[]'::jsonb,'print_images','[]'::jsonb,
              'sticker_images','[]'::jsonb,'metal_id_images','[]'::jsonb,'actions',v_actions,
              'rate_gate',case when coalesce(v_assignment.actual_rate,0)>0 then 'READY' else 'FIRST_SUBMIT_RATE_REQUIRED' end,
              'canonical_source','rr_upm_work_assignments_v8'));
          end if;
          v_count := v_count+1;
        end loop;
        exit when v_count>=v_cap;
      end loop;
      exit when v_count>=v_cap;
    end loop;
  else
    for v_assignment in
      select a.* from public.rr_upm_work_assignments_v8 a
      where a.status in ('COMPLETED','CANCELLED')
        and (nullif(trim(p_department_code),'') is null or public.rr_upm_core_department_v9077(a.department_code)=public.rr_upm_core_department_v9077(p_department_code))
        and (v_global or a.worker_id=v_worker or public.rr_upm_core_department_v9077(a.department_code)=v_home)
        and (v_staff or a.worker_id=v_worker)
        and (v_find='' or lower(concat_ws(' ',a.lot_no,a.colour_code,a.colour_name,a.worker_name_snapshot,a.department_code,a.status)) like '%'||v_find||'%')
      order by coalesce(a.completed_at,a.cancelled_at,a.updated_at,a.assigned_at) desc
      limit v_cap
    loop
      v_dept := public.rr_upm_core_department_v9077(v_assignment.department_code);
      v_actions := '[]'::jsonb;
      v_link := 'real-universal-production-v770-v9059.html?mode=TEST&dept='||v_dept||'&from=TEST70_REAL_CHAT';
      if v_assignment.status='COMPLETED' and v_role in ('ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD') then
        v_actions := v_actions || jsonb_build_array(jsonb_build_object(
          'code','RECTIFICATION','label','RECTIFICATION','href',v_link||'&rrMode=SUBMIT',
          'engine','rr_upm_open_rectification_v9110'));
      end if;
      if v_assignment.status='COMPLETED' and v_dept in ('PACKING','DISPATCH') and v_role='ADMIN' then
        v_actions := v_actions || jsonb_build_array(jsonb_build_object(
          'code','FINAL_SALE_RATE_RRQ','label','FINAL SALE RATE / RRQ',
          'href','real-finished-goods-v787.html?view=packing&from=TEST70_REAL_CHAT',
          'engine','EXISTING_PACKING_RRQ_WORKFLOW'));
      end if;
      v_cards := v_cards || jsonb_build_array(jsonb_build_object(
        'event_key','UPM_ASSIGNMENT:'||v_assignment.id,'source_module','UNIVERSAL_PRODUCTION',
        'original_record_id',v_assignment.id,'canonical_lot_id',v_assignment.canonical_lot_id,
        'lot_no',v_assignment.lot_no,'department_code',v_dept,'department_name',v_dept,
        'colour_code',v_assignment.colour_code,'colour_name',v_assignment.colour_name,
        'worker_id',v_assignment.worker_id,'worker_name',v_assignment.worker_name_snapshot,
        'qty',greatest(coalesce(v_assignment.inbound_qty,0),coalesce(v_assignment.assigned_qty,0)),
        'actual_rate',v_assignment.actual_rate,'source_status',v_assignment.status,'chat_status','CLOSE',
        'sender_user_id',v_assignment.assigned_by,'sender_name',v_assignment.assigned_by_name,
        'event_at',coalesce(v_assignment.completed_at,v_assignment.cancelled_at,v_assignment.updated_at),
        'art_images','[]'::jsonb,'print_images','[]'::jsonb,'sticker_images','[]'::jsonb,'metal_id_images','[]'::jsonb,
        'actions',v_actions,'canonical_source','rr_upm_work_assignments_v8'));
    end loop;
  end if;

  -- Pending remake/alter custody stays actionable after the main submission card moves to CLOSE.
  if v_state='WORKING' then
    for v_journey in
      select j.* from public.rr_upm_alter_journey_v740 j
      where j.stage not like 'CLOSED%'
        and (nullif(trim(p_department_code),'') is null or public.rr_upm_core_department_v9077(j.origin_department_code)=public.rr_upm_core_department_v9077(p_department_code))
        and (v_global or j.responsible_id=v_worker or j.karigar_id=v_worker or public.rr_upm_core_department_v9077(j.origin_department_code)=v_home)
      order by j.updated_at desc limit greatest(v_cap-v_count,0)
    loop
      v_dept := public.rr_upm_core_department_v9077(v_journey.origin_department_code);
      v_actions := '[]'::jsonb;
      v_link := 'real-universal-production-v770-v9059.html?mode=TEST&dept='||v_dept||'&from=TEST70_REAL_CHAT';
      if v_journey.stage='LM_ALTER_PENDING' and v_role in ('ADMIN','CUTTING_MASTER') then
        v_actions := jsonb_build_array(jsonb_build_object('code','REMAKE_ISSUE','label','REMAKE ISSUE · CM','href',v_link,'engine','rr_upm_alter_stage_v740'));
      elsif v_journey.stage='CM_REMAKE_READY' and v_role in ('ADMIN','MANAGER','LINE_MANAGER','LINE_MAN') then
        v_actions := jsonb_build_array(jsonb_build_object('code','RECEIVE_MASTER','label','RECEIVE MASTER · LM','href',v_link,'engine','rr_upm_alter_stage_v740'));
      elsif v_journey.stage='LM_DELIVERY_PENDING' and v_role in ('ADMIN','MANAGER','LINE_MANAGER','LINE_MAN') then
        v_actions := jsonb_build_array(jsonb_build_object('code','DELIVER_KARIGAR','label','DELIVER KARIGAR · LM','href',v_link,'engine','rr_upm_alter_stage_v740'));
      elsif v_journey.stage='KARIGAR_REMAKE_PENDING' and v_role in ('ADMIN','MANAGER','LINE_MANAGER','LINE_MAN') then
        v_actions := jsonb_build_array(jsonb_build_object('code','RECEIVE_KARIGAR','label','RECEIVE KARIGAR · LM','href',v_link,'engine','rr_upm_alter_stage_v740'));
      end if;
      if v_find='' or lower(concat_ws(' ',v_journey.lot_no,v_journey.colour_code,v_journey.colour_name,v_journey.responsible_name,v_dept,v_journey.stage)) like '%'||v_find||'%' then
        v_cards := v_cards || jsonb_build_array(jsonb_build_object(
          'event_key','UPM_ALTER:'||v_journey.id,'source_module','UPM_ALTER_JOURNEY',
          'original_record_id',v_journey.id,'canonical_lot_id',v_journey.canonical_lot_id,
          'lot_no',v_journey.lot_no,'department_code',v_dept,'department_name',v_dept,
          'colour_code',v_journey.colour_code,'colour_name',v_journey.colour_name,
          'worker_id',coalesce(v_journey.responsible_id,v_journey.karigar_id),
          'worker_name',coalesce(v_journey.responsible_name,v_journey.karigar_name),
          'qty',v_journey.open_qty,'actual_rate',null,'source_status',v_journey.stage,'chat_status','WORKING',
          'event_at',v_journey.updated_at,'art_images',coalesce(v_journey.evidence_urls,'[]'::jsonb),
          'print_images','[]'::jsonb,'sticker_images','[]'::jsonb,'metal_id_images','[]'::jsonb,
          'actions',v_actions,'canonical_source','rr_upm_alter_journey_v740'));
      end if;
    end loop;
  end if;

  select coalesce(jsonb_object_agg(department_code,cnt),'{}'::jsonb) into v_counts
  from (select x->>'department_code' department_code,count(*) cnt from jsonb_array_elements(v_cards) x group by 1) s;

  return jsonb_build_object(
    'version','TEST70_REAL_CHAT_WORK_V71_CANONICAL','read_only_projection',true,
    'canonical_open_source','rr_upm_colour_queue_v741','canonical_action_mode','EXISTING_WORKFLOW_DEEP_LINK',
    'actor',jsonb_build_object('profile_id',v_profile.id,'user_id',v_uid,'worker_id',v_worker,'name',v_profile.full_name,'role',v_role,'department_code',v_home,'is_staff',v_staff),
    'status',v_state,'cards',v_cards,'department_counts',v_counts);
end
$function$;

revoke all on function public.rr_real_chat_work_inbox_v71(text,text,text,integer) from public, anon;
grant execute on function public.rr_real_chat_work_inbox_v71(text,text,text,integer) to authenticated;
comment on function public.rr_real_chat_work_inbox_v71(text,text,text,integer) is
  'TEST70-only Real Chat projection. OPEN uses the canonical production colour queue through rr_upm_department_colour_due_card_v9109; actions deep-link to existing production engines.';

insert into public.rr_real_chat_action_registry_v70
  (action_code,exact_button_label,source_module,source_page,rpc_name,allowed_roles,registry_status,notes)
values
 ('ASSIGN_WORKER','ASSIGN WORKER','UPM','real-upm-department-view-v789.js','rr_upm_ready_to_assign_v9107',array['ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD','CUTTING_MASTER'],'ACTIVE','Canonical OPEN queue; first assignment wins'),
 ('SUBMIT','SUBMIT','UPM','real-upm-department-view-v789.js','rr_upm_submit_colours_v741',array['ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD','WORKER'],'ACTIVE','First submission remains protected by rate gate'),
 ('ALTER_FILL','ALTER','UPM','real-upm-department-view-v789.js','rr_upm_alter_stage_v740',array['ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD'],'ACTIVE','Existing alter journey engine'),
 ('RECTIFICATION','RECTIFICATION','UPM','real-upm-department-view-v789.js','rr_upm_open_rectification_v9110',array['ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD'],'ACTIVE','Existing rectification engine'),
 ('DEPARTMENT_RATE','FILL DEPARTMENT RATE','UPM_COSTING','real-upm-costing-v9300.js','rr_upm_set_department_rate_v760',array['MANAGER'],'ACTIVE','One lot + canonical department rate applies to every colour; Manager owned'),
 ('FINAL_SALE_RATE_RRQ','FINAL SALE RATE / RRQ','PACKING','real-finished-goods-v787.html','EXISTING_PACKING_RRQ_WORKFLOW',array['ADMIN'],'ACTIVE','Final Sale Rate approval and RRQ remain Admin owned'),
 ('REMAKE_ISSUE','REMAKE ISSUE · CM','UPM','real-upm-department-view-v789.js','rr_upm_alter_stage_v740',array['ADMIN','CUTTING_MASTER'],'ACTIVE','Visible only at LM_ALTER_PENDING'),
 ('RECEIVE_MASTER','RECEIVE MASTER · LM','UPM','real-upm-department-view-v789.js','rr_upm_alter_stage_v740',array['ADMIN','MANAGER','LINE_MANAGER','LINE_MAN'],'ACTIVE','Visible only at CM_REMAKE_READY'),
 ('DELIVER_KARIGAR','DELIVER KARIGAR · LM','UPM','real-upm-department-view-v789.js','rr_upm_alter_stage_v740',array['ADMIN','MANAGER','LINE_MANAGER','LINE_MAN'],'ACTIVE','Visible only at LM_DELIVERY_PENDING'),
 ('RECEIVE_KARIGAR','RECEIVE KARIGAR · LM','UPM','real-upm-department-view-v789.js','rr_upm_alter_stage_v740',array['ADMIN','MANAGER','LINE_MANAGER','LINE_MAN'],'ACTIVE','Visible only at KARIGAR_REMAKE_PENDING')
on conflict(action_code) do update set
  exact_button_label=excluded.exact_button_label,source_module=excluded.source_module,
  source_page=excluded.source_page,rpc_name=excluded.rpc_name,allowed_roles=excluded.allowed_roles,
  registry_status=excluded.registry_status,notes=excluded.notes,updated_at=now();

commit;
