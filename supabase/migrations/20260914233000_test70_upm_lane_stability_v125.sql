begin;

create or replace function public.rr_real_chat_work_inbox_v75(
  p_status text default 'WORKING', p_search text default null,
  p_department_code text default null, p_limit integer default 500
)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_base jsonb; v_cards jsonb:='[]'::jsonb; v_card jsonb; v_actions jsonb; v_counts jsonb;
  v_assignment public.rr_upm_work_assignments_v8%rowtype;
  v_rect public.rr_upm_rectification_cases_v9101%rowtype;
  v_j public.rr_upm_alter_journey_v740%rowtype;
  v_state text:=upper(trim(coalesce(p_status,'WORKING'))); v_role text; v_home text;
  v_worker uuid; v_global boolean; v_staff boolean; v_dept text; v_link text; v_can_close boolean;
  v_cap integer:=least(greatest(coalesce(p_limit,500),1),500);
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  if v_state not in ('OPEN','WORKING','CLOSE') then raise exception 'Status must be OPEN, WORKING or CLOSE.'; end if;
  v_base:=public.rr_real_chat_work_inbox_v74(v_state,p_search,p_department_code,v_cap);
  v_role:=upper(coalesce(v_base#>>'{actor,role}','WORKER'));
  v_worker:=nullif(v_base#>>'{actor,worker_id}','')::uuid;
  v_home:=public.rr_upm_core_department_v9077(v_base#>>'{actor,department_code}');
  v_global:=v_role in ('OWNER','SUPER_ADMIN','ADMIN');
  v_staff:=v_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD','PRODUCTION','CUTTING_MASTER');

  -- Normalize inherited rows. Exception-flavoured assignments are rebuilt only
  -- from their canonical Alter or Rectification source below.
  for v_card in select value from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb)) loop
    if v_card->>'canonical_source'='rr_upm_work_assignments_v8' and nullif(v_card->>'original_record_id','') is not null then
      select * into v_assignment from public.rr_upm_work_assignments_v8 where id=(v_card->>'original_record_id')::uuid;
      if found and upper(trim(coalesce(v_assignment.source_type,''))) in ('RECTIFICATION','ALTER') then continue; end if;
      if found then
        v_dept:=public.rr_upm_core_department_v9077(v_assignment.department_code);
        v_link:='real-universal-production-v770-v9059.html?mode=TEST&dept='||v_dept||'&from=TEST70_REAL_CHAT&rrMode=SUBMIT&rrOpenSubmit='||v_assignment.canonical_lot_id;
        v_actions:='[]'::jsonb;
        if v_state='WORKING' and (v_assignment.worker_id=v_worker or v_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD')) then
          v_actions:=jsonb_build_array(jsonb_build_object('code','SUBMIT','label','SUBMIT','href',v_link,'engine','rr_upm_submit_colours_v741'));
        end if;
        if v_state='WORKING' and v_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD') then
          v_actions:=v_actions||jsonb_build_array(
            jsonb_build_object('code','ALTER_FILL','label','ALTER','href',v_link,'engine','rr_upm_alter_stage_v740'),
            jsonb_build_object('code','RECTIFICATION','label','RECTIFICATION','href',v_link,'engine','rr_upm_open_rectification_v9110'));
        elsif v_state='CLOSE' and upper(coalesce(v_assignment.status,''))='COMPLETED' and v_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD') then
          v_actions:=jsonb_build_array(jsonb_build_object('code','RECTIFICATION','label','RECTIFICATION','href',v_link,'engine','rr_upm_open_rectification_v9110'));
        end if;
        v_card:=v_card||jsonb_build_object('work_category','READY_TO_SUBMIT','actions',v_actions);
      end if;
    elsif v_card->>'canonical_source'='rr_upm_rectification_cases_v9101' then
      continue;
    elsif v_card->>'canonical_source'='rr_upm_alter_journey_v740' then
      v_card:=v_card||jsonb_build_object('work_category','ALTER');
    elsif v_state='OPEN' and v_card->>'source_module'='UNIVERSAL_PRODUCTION' then
      v_card:=v_card||jsonb_build_object('work_category','READY_TO_ASSIGN');
    end if;
    v_cards:=v_cards||jsonb_build_array(v_card);
  end loop;

  -- Regular gets an independent capacity. A full base snapshot cannot starve it.
  if v_state in ('WORKING','CLOSE') then
    for v_assignment in select a.* from public.rr_upm_work_assignments_v8 a
      where ((v_state='WORKING' and upper(coalesce(a.status,'')) in ('ASSIGNED','IN_PROGRESS'))
          or (v_state='CLOSE' and upper(coalesce(a.status,'')) in ('COMPLETED','CANCELLED','RELEASED')))
        and upper(trim(coalesce(a.source_type,''))) not in ('RECTIFICATION','ALTER')
        and (nullif(trim(p_department_code),'') is null or public.rr_upm_core_department_v9077(a.department_code)=public.rr_upm_core_department_v9077(p_department_code))
        and (v_global or a.worker_id=v_worker or public.rr_upm_core_department_v9077(a.department_code)=v_home)
        and (v_staff or a.worker_id=v_worker)
        and (coalesce(trim(p_search),'')='' or lower(concat_ws(' ',a.lot_no,a.colour_code,a.colour_name,a.worker_name_snapshot,a.department_code,a.status)) like '%'||lower(trim(p_search))||'%')
      order by coalesce(a.completed_at,a.cancelled_at,a.updated_at,a.assigned_at) desc limit v_cap
    loop
      if not exists(select 1 from jsonb_array_elements(v_cards) c where c->>'event_key'='UPM_ASSIGNMENT:'||v_assignment.id) then
        v_dept:=public.rr_upm_core_department_v9077(v_assignment.department_code);
        v_link:='real-universal-production-v770-v9059.html?mode=TEST&dept='||v_dept||'&from=TEST70_REAL_CHAT&rrMode=SUBMIT&rrOpenSubmit='||v_assignment.canonical_lot_id;
        v_actions:='[]'::jsonb;
        if v_state='WORKING' and (v_assignment.worker_id=v_worker or v_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD')) then
          v_actions:=jsonb_build_array(jsonb_build_object('code','SUBMIT','label','SUBMIT','href',v_link,'engine','rr_upm_submit_colours_v741'));
        end if;
        if v_state='WORKING' and v_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD') then
          v_actions:=v_actions||jsonb_build_array(
            jsonb_build_object('code','ALTER_FILL','label','ALTER','href',v_link,'engine','rr_upm_alter_stage_v740'),
            jsonb_build_object('code','RECTIFICATION','label','RECTIFICATION','href',v_link,'engine','rr_upm_open_rectification_v9110'));
        elsif v_state='CLOSE' and upper(coalesce(v_assignment.status,''))='COMPLETED' and v_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD') then
          v_actions:=jsonb_build_array(jsonb_build_object('code','RECTIFICATION','label','RECTIFICATION','href',v_link,'engine','rr_upm_open_rectification_v9110'));
        end if;
        v_cards:=v_cards||jsonb_build_array(jsonb_build_object(
          'event_key','UPM_ASSIGNMENT:'||v_assignment.id,'source_module','UNIVERSAL_PRODUCTION','original_record_id',v_assignment.id,
          'canonical_lot_id',v_assignment.canonical_lot_id,'lot_no',v_assignment.lot_no,'department_code',v_dept,'department_name',v_dept,
          'colour_code',v_assignment.colour_code,'colour_name',v_assignment.colour_name,'worker_id',v_assignment.worker_id,'worker_name',v_assignment.worker_name_snapshot,
          'qty',greatest(coalesce(v_assignment.inbound_qty,0),coalesce(v_assignment.assigned_qty,0)),'actual_rate',v_assignment.actual_rate,
          'source_status',v_assignment.status,'chat_status',v_state,'work_category','READY_TO_SUBMIT',
          'event_at',coalesce(v_assignment.completed_at,v_assignment.cancelled_at,v_assignment.updated_at,v_assignment.assigned_at),'actions',v_actions,
          'rate_gate',case when coalesce(v_assignment.actual_rate,0)>0 then 'READY' else 'FIRST_SUBMIT_RATE_REQUIRED' end,
          'canonical_source','rr_upm_work_assignments_v8'));
      end if;
    end loop;
  end if;

  -- Rectification has explicit active/terminal sets and its own capacity.
  if v_state in ('WORKING','CLOSE') then
    for v_rect in select r.* from public.rr_upm_rectification_cases_v9101 r
      where ((v_state='WORKING' and upper(trim(coalesce(r.status,'OPEN'))) in ('OPEN','ASSIGNED','IN_PROGRESS','REOPENED','RESUBMITTED','PENDING'))
          or (v_state='CLOSE' and upper(trim(coalesce(r.status,''))) in ('CLOSED','CANCELLED','REJECTED','VOID','MERGED','RESOLVED')))
        and (nullif(trim(p_department_code),'') is null or public.rr_upm_core_department_v9077(coalesce(r.target_department_code,r.origin_department_code))=public.rr_upm_core_department_v9077(p_department_code))
        and (v_global or r.assigned_worker_id=v_worker or r.original_worker_id=v_worker or public.rr_upm_core_department_v9077(coalesce(r.target_department_code,r.origin_department_code))=v_home)
        and (coalesce(trim(p_search),'')='' or lower(concat_ws(' ',r.lot_no,r.colour_code,r.size_code,r.original_worker_name,r.assigned_worker_name,r.reason,r.status)) like '%'||lower(trim(p_search))||'%')
      order by coalesce(r.closed_at,r.resubmitted_at,r.assigned_at,r.created_at) desc limit v_cap
    loop
      v_dept:=public.rr_upm_core_department_v9077(coalesce(v_rect.target_department_code,v_rect.origin_department_code));
      v_can_close:=v_state='WORKING' and (v_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD') or v_worker=v_rect.assigned_worker_id or v_worker=v_rect.line_man_id);
      v_actions:=case when v_can_close then jsonb_build_array(jsonb_build_object('code','RECTIFICATION_FINAL_CLOSE','label','RECTIFICATION · FINAL CLOSE','href','test70-rectification-close-v123.html?case_id='||v_rect.id,'engine','rr_real_chat_close_rectification_v1')) else '[]'::jsonb end;
      v_cards:=v_cards||jsonb_build_array(jsonb_build_object(
        'event_key','UPM_RECTIFICATION:'||v_rect.id,'source_module','UPM_RECTIFICATION','original_record_id',v_rect.id,'canonical_lot_id',v_rect.canonical_lot_id,
        'lot_no',v_rect.lot_no,'department_code',v_dept,'department_name',v_dept,'origin_department_code',v_rect.origin_department_code,
        'colour_code',v_rect.colour_code,'colour_name',v_rect.colour_code,'size_code',v_rect.size_code,
        'worker_id',coalesce(v_rect.assigned_worker_id,v_rect.original_worker_id),'worker_name',coalesce(v_rect.assigned_worker_name,v_rect.original_worker_name),
        'qty',greatest(coalesce(v_rect.recalled_good_qty,0),coalesce(v_rect.resubmitted_good_qty,0)),'recalled_good_qty',v_rect.recalled_good_qty,
        'resubmitted_good_qty',v_rect.resubmitted_good_qty,'damage_qty',v_rect.damage_qty,'alter_qty',v_rect.alter_qty,
        'rectification_case_id',v_rect.id,'source_status',v_rect.status,'chat_status',v_state,'work_category','RECTIFICATION',
        'message',v_rect.reason,'event_at',coalesce(v_rect.closed_at,v_rect.resubmitted_at,v_rect.assigned_at,v_rect.created_at),
        'evidence_urls',coalesce(v_rect.evidence_urls,'[]'::jsonb),'actions',v_actions,
        'action_waiting',case when v_state='WORKING' and not v_can_close then 'WAITING FOR ASSIGNED WORKER / LINE MAN' else null end,
        'canonical_source','rr_upm_rectification_cases_v9101'));
    end loop;
  end if;

  -- Closed Alter is source-truth CLOSE, not dependent on bridge history.
  if v_state='CLOSE' then
    for v_j in select j.* from public.rr_upm_alter_journey_v740 j
      where upper(coalesce(j.stage,'')) like 'CLOSED%' and coalesce(j.open_qty,0)>0
        and (nullif(trim(p_department_code),'') is null or public.rr_upm_core_department_v9077(j.origin_department_code)=public.rr_upm_core_department_v9077(p_department_code))
        and (v_global or v_worker in (j.responsible_id,j.karigar_id,j.enrolled_lm_id,j.cutting_master_id) or public.rr_upm_core_department_v9077(j.origin_department_code)=v_home)
        and (coalesce(trim(p_search),'')='' or lower(concat_ws(' ',j.lot_no,j.colour_code,j.colour_name,j.size_code,j.responsible_name,j.close_reason,j.stage)) like '%'||lower(trim(p_search))||'%')
      order by coalesce(j.closed_at,j.updated_at) desc limit v_cap
    loop
      if not exists(select 1 from jsonb_array_elements(v_cards) c where c->>'event_key'='UPM_ALTER:'||v_j.id) then
        v_dept:=public.rr_upm_core_department_v9077(v_j.origin_department_code);
        v_cards:=v_cards||jsonb_build_array(jsonb_build_object(
          'event_key','UPM_ALTER:'||v_j.id,'source_module','UPM_ALTER_JOURNEY','original_record_id',v_j.id,'canonical_lot_id',v_j.canonical_lot_id,
          'lot_no',v_j.lot_no,'department_code',v_dept,'department_name',v_dept,'colour_code',v_j.colour_code,'colour_name',v_j.colour_name,
          'size_code',v_j.size_code,'worker_id',coalesce(v_j.responsible_id,v_j.karigar_id),'worker_name',coalesce(v_j.responsible_name,v_j.karigar_name),
          'qty',v_j.open_qty,'source_status',v_j.stage,'chat_status','CLOSE','work_category','ALTER','message',v_j.close_reason,
          'event_at',coalesce(v_j.closed_at,v_j.updated_at),'evidence_urls',coalesce(v_j.evidence_urls,'[]'::jsonb),'actions','[]'::jsonb,
          'canonical_source','rr_upm_alter_journey_v740'));
      end if;
    end loop;
  end if;

  select coalesce(jsonb_object_agg(department_code,cnt),'{}'::jsonb) into v_counts
  from (select coalesce(nullif(x->>'department_code',''),'UNKNOWN') department_code,count(*) cnt from jsonb_array_elements(v_cards) x group by 1)s;
  return jsonb_set(jsonb_set(jsonb_set(v_base,'{version}','"TEST70_REAL_CHAT_WORK_V75_LANE_STABLE"'::jsonb,true),'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end;
$$;
revoke all on function public.rr_real_chat_work_inbox_v75(text,text,text,integer) from public;
revoke all on function public.rr_real_chat_work_inbox_v75(text,text,text,integer) from anon;
grant execute on function public.rr_real_chat_work_inbox_v75(text,text,text,integer) to authenticated;

create or replace function public.rr_real_chat_work_search_v5(p_status text default 'WORKING',p_search text default null,p_department_code text default null,p_limit integer default 500)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_base jsonb; v_find text:=lower(trim(coalesce(p_search,''))); v_key text:=regexp_replace(lower(trim(coalesce(p_search,''))),'[^a-z0-9]','','g'); v_cards jsonb; v_counts jsonb;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  v_base:=public.rr_real_chat_work_inbox_v75(p_status,null,p_department_code,p_limit);
  if v_find='' then return v_base; end if;
  select coalesce(jsonb_agg(card order by ord),'[]'::jsonb) into v_cards from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb)) with ordinality x(card,ord)
  where lower(card::text) like '%'||v_find||'%' or (v_key<>'' and regexp_replace(lower(card::text),'[^a-z0-9]','','g') like '%'||v_key||'%');
  select coalesce(jsonb_object_agg(department_code,card_count),'{}'::jsonb) into v_counts from (select coalesce(nullif(card->>'department_code',''),'UNKNOWN') department_code,count(*) card_count from jsonb_array_elements(v_cards) x(card) group by 1)c;
  return jsonb_set(jsonb_set(v_base,'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end;
$$;
revoke all on function public.rr_real_chat_work_search_v5(text,text,text,integer) from public;
revoke all on function public.rr_real_chat_work_search_v5(text,text,text,integer) from anon;
grant execute on function public.rr_real_chat_work_search_v5(text,text,text,integer) to authenticated;

-- The currently deployed TEST70 adapter still calls V4. Keep that public
-- contract live while routing it through the corrected V75 projection, so the
-- database fix is effective before the next Git/Vercel source deployment.
create or replace function public.rr_real_chat_work_search_v4(
  p_status text default 'WORKING',p_search text default null,
  p_department_code text default null,p_limit integer default 500
)
returns jsonb language sql stable security definer set search_path='' as $$
  select public.rr_real_chat_work_search_v5(p_status,p_search,p_department_code,p_limit)
$$;
revoke all on function public.rr_real_chat_work_search_v4(text,text,text,integer) from public;
revoke all on function public.rr_real_chat_work_search_v4(text,text,text,integer) from anon;
grant execute on function public.rr_real_chat_work_search_v4(text,text,text,integer) to authenticated;

insert into public.rr_real_chat_action_registry_v70(action_code,exact_button_label,source_module,source_page,rpc_name,allowed_roles,registry_status,notes)
values
 ('SUBMIT','SUBMIT','UPM','real-upm-department-view-v789.js','rr_upm_submit_colours_v741',array['OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD','WORKER'],'ACTIVE','Canonical WORKING action; rate gate remains enforced'),
 ('ALTER_FILL','ALTER','UPM','real-upm-department-view-v789.js','rr_upm_alter_stage_v740',array['OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD'],'ACTIVE','Starts canonical Alter'),
 ('RECTIFICATION','RECTIFICATION','UPM','real-upm-department-view-v789.js','rr_upm_open_rectification_v9110',array['OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD'],'ACTIVE','Opens canonical Rectification'),
 ('RECTIFICATION_FINAL_CLOSE','RECTIFICATION · FINAL CLOSE','UPM_RECTIFICATION','test70-rectification-close-v123.html','rr_real_chat_close_rectification_v1',array['OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD','ASSIGNED_WORKER'],'ACTIVE','Emitted only when RPC authorization passes')
on conflict(action_code) do update set exact_button_label=excluded.exact_button_label,source_module=excluded.source_module,source_page=excluded.source_page,rpc_name=excluded.rpc_name,allowed_roles=excluded.allowed_roles,registry_status=excluded.registry_status,notes=excluded.notes,updated_at=now();

commit;
