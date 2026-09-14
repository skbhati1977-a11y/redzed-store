begin;

create or replace function public.rr_real_chat_work_inbox_v73(
  p_status text default 'WORKING', p_search text default null,
  p_department_code text default null, p_limit integer default 500
)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_base jsonb; v_cards jsonb:='[]'::jsonb; v_counts jsonb;
  v_card jsonb; v_actions jsonb; v_assignment public.rr_upm_work_assignments_v8%rowtype;
  v_rect public.rr_upm_rectification_cases_v9101%rowtype;
  v_state text:=upper(trim(coalesce(p_status,'WORKING'))); v_role text; v_home text;
  v_worker uuid; v_global boolean; v_staff boolean; v_dept text; v_link text; v_source_type text;
  v_cap integer:=least(greatest(coalesce(p_limit,500),1),500);
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  v_base:=public.rr_real_chat_work_inbox_v72(v_state,p_search,p_department_code,v_cap);
  v_role:=upper(coalesce(v_base#>>'{actor,role}','WORKER'));
  v_worker:=nullif(v_base#>>'{actor,worker_id}','')::uuid;
  v_home:=public.rr_upm_core_department_v9077(v_base#>>'{actor,department_code}');
  v_global:=v_role in ('OWNER','SUPER_ADMIN','ADMIN');
  v_staff:=v_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD','PRODUCTION','CUTTING_MASTER');

  if v_state='OPEN' then
    -- Preserve the canonical UPM READY TO ASSIGN eligibility for each department.
    v_cards:=coalesce(v_base->'cards','[]'::jsonb);
  else
    v_cards:=coalesce(v_base->'cards','[]'::jsonb);
  end if;

  if v_state='WORKING' then
    -- Direct assignment truth: no active assignment may disappear because of a due-card snapshot.
    for v_assignment in
      select a.* from public.rr_upm_work_assignments_v8 a
      where a.status in ('ASSIGNED','IN_PROGRESS')
        and coalesce(a.source_type,'')<>'RECTIFICATION'
        and (nullif(trim(p_department_code),'') is null
          or public.rr_upm_core_department_v9077(a.department_code)=public.rr_upm_core_department_v9077(p_department_code))
        and (v_global or a.worker_id=v_worker or public.rr_upm_core_department_v9077(a.department_code)=v_home)
        and (v_staff or a.worker_id=v_worker)
        and (coalesce(trim(p_search),'')='' or lower(concat_ws(' ',a.lot_no,a.colour_code,a.colour_name,a.worker_name_snapshot,a.department_code,a.status)) like '%'||lower(trim(p_search))||'%')
        and not exists(select 1 from jsonb_array_elements(v_cards) c where c->>'event_key'='UPM_ASSIGNMENT:'||a.id)
      order by a.assigned_at desc
      limit greatest(v_cap-jsonb_array_length(v_cards),0)
    loop
      v_dept:=public.rr_upm_core_department_v9077(v_assignment.department_code);
      v_link:='real-universal-production-v770-v9059.html?mode=TEST&dept='||v_dept||
        '&from=TEST70_REAL_CHAT&rrMode=SUBMIT&rrOpenSubmit='||v_assignment.canonical_lot_id;
      v_actions:='[]'::jsonb;
      if v_assignment.worker_id=v_worker or v_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD') then
        v_actions:=v_actions||jsonb_build_array(jsonb_build_object(
          'code','SUBMIT','label','READY TO SUBMIT','href',v_link,'engine','rr_upm_submit_colours_v741'));
      end if;
      if v_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD') then
        v_actions:=v_actions||jsonb_build_array(
          jsonb_build_object('code','ALTER_FILL','label','ALTER','href',v_link,'engine','rr_upm_alter_stage_v740'),
          jsonb_build_object('code','RECTIFICATION','label','RECTIFICATION','href',v_link,'engine','rr_upm_open_rectification_v9110'));
      end if;
      v_cards:=v_cards||jsonb_build_array(jsonb_build_object(
        'event_key','UPM_ASSIGNMENT:'||v_assignment.id,'source_module','UNIVERSAL_PRODUCTION',
        'original_record_id',v_assignment.id,'canonical_lot_id',v_assignment.canonical_lot_id,
        'lot_no',v_assignment.lot_no,'department_code',v_dept,'department_name',v_dept,
        'colour_code',v_assignment.colour_code,'colour_name',v_assignment.colour_name,
        'worker_id',v_assignment.worker_id,'worker_name',v_assignment.worker_name_snapshot,
        'qty',greatest(coalesce(v_assignment.inbound_qty,0),coalesce(v_assignment.assigned_qty,0)),
        'actual_rate',v_assignment.actual_rate,'source_status',v_assignment.status,
        'chat_status','WORKING','work_category','READY_TO_SUBMIT','event_at',v_assignment.assigned_at,
        'actions',v_actions,'rate_gate',case when coalesce(v_assignment.actual_rate,0)>0 then 'READY' else 'FIRST_SUBMIT_RATE_REQUIRED' end,
        'canonical_source','rr_upm_work_assignments_v8'));
    end loop;
  end if;

  -- Rectification is a separate lane, never mixed into Regular or Alter.
  if v_state in ('WORKING','CLOSE') then
    for v_rect in
      select r.* from public.rr_upm_rectification_cases_v9101 r
      where ((v_state='WORKING' and upper(coalesce(r.status,'OPEN'))<>'CLOSED')
          or (v_state='CLOSE' and upper(coalesce(r.status,'OPEN'))='CLOSED'))
        and (nullif(trim(p_department_code),'') is null
          or public.rr_upm_core_department_v9077(coalesce(r.target_department_code,r.origin_department_code))=public.rr_upm_core_department_v9077(p_department_code))
        and (v_global or r.assigned_worker_id=v_worker or r.original_worker_id=v_worker
          or public.rr_upm_core_department_v9077(coalesce(r.target_department_code,r.origin_department_code))=v_home)
        and (coalesce(trim(p_search),'')='' or lower(concat_ws(' ',r.lot_no,r.colour_code,r.size_code,r.original_worker_name,r.assigned_worker_name,r.reason,r.status)) like '%'||lower(trim(p_search))||'%')
        and not exists(select 1 from jsonb_array_elements(v_cards) c where c->>'event_key'='UPM_RECTIFICATION:'||r.id)
      order by coalesce(r.closed_at,r.resubmitted_at,r.assigned_at,r.created_at) desc
      limit greatest(v_cap-jsonb_array_length(v_cards),0)
    loop
      v_dept:=public.rr_upm_core_department_v9077(coalesce(v_rect.target_department_code,v_rect.origin_department_code));
      v_link:='real-universal-production-v770-v9059.html?mode=TEST&dept='||v_dept||
        '&from=TEST70_REAL_CHAT&rrMode=SUBMIT&rrOpenSubmit='||v_rect.canonical_lot_id;
      v_actions:=case when v_state='WORKING' then jsonb_build_array(jsonb_build_object(
        'code','RECTIFICATION_FINAL_CLOSE','label','RECTIFICATION · FINAL CLOSE',
        'href','test70-rectification-close-v123.html?case_id='||v_rect.id,
        'engine','rr_real_chat_close_rectification_v1')) else '[]'::jsonb end;
      v_cards:=v_cards||jsonb_build_array(jsonb_build_object(
        'event_key','UPM_RECTIFICATION:'||v_rect.id,'source_module','UPM_RECTIFICATION',
        'original_record_id',v_rect.id,'canonical_lot_id',v_rect.canonical_lot_id,
        'lot_no',v_rect.lot_no,'department_code',v_dept,'department_name',v_dept,
        'origin_department_code',v_rect.origin_department_code,
        'colour_code',v_rect.colour_code,'colour_name',v_rect.colour_code,'size_code',v_rect.size_code,
        'worker_id',coalesce(v_rect.assigned_worker_id,v_rect.original_worker_id),
        'worker_name',coalesce(v_rect.assigned_worker_name,v_rect.original_worker_name),
        'qty',greatest(coalesce(v_rect.recalled_good_qty,0),coalesce(v_rect.resubmitted_good_qty,0)),
        'recalled_good_qty',v_rect.recalled_good_qty,'resubmitted_good_qty',v_rect.resubmitted_good_qty,
        'damage_qty',v_rect.damage_qty,'alter_qty',v_rect.alter_qty,'rectification_case_id',v_rect.id,
        'source_status',v_rect.status,'chat_status',v_state,'work_category','RECTIFICATION',
        'message',v_rect.reason,'event_at',coalesce(v_rect.closed_at,v_rect.resubmitted_at,v_rect.assigned_at,v_rect.created_at),
        'evidence_urls',coalesce(v_rect.evidence_urls,'[]'::jsonb),'actions',v_actions,
        'canonical_source','rr_upm_rectification_cases_v9101'));
    end loop;
  end if;

  -- Normalize every existing card into exactly one UPM lane.
  v_base:=jsonb_set(v_base,'{cards}',v_cards,true); v_cards:='[]'::jsonb;
  for v_card in select value from jsonb_array_elements(v_base->'cards') loop
    v_source_type:=null;
    if v_card->>'canonical_source'='rr_upm_work_assignments_v8' and nullif(v_card->>'original_record_id','') is not null then
      select a.source_type into v_source_type from public.rr_upm_work_assignments_v8 a
      where a.id=(v_card->>'original_record_id')::uuid;
      if v_source_type='RECTIFICATION' then continue; end if;
    end if;
    if v_card->>'work_category' is null then
      v_card:=jsonb_set(v_card,'{work_category}',
        to_jsonb(case
          when v_card->>'canonical_source'='rr_upm_alter_journey_v740' then 'ALTER'
          when v_card->>'canonical_source'='rr_upm_rectification_cases_v9101' then 'RECTIFICATION'
          when v_state='OPEN' then 'READY_TO_ASSIGN'
          else 'READY_TO_SUBMIT' end),true);
    end if;
    v_cards:=v_cards||jsonb_build_array(v_card);
  end loop;
  select coalesce(jsonb_object_agg(department_code,cnt),'{}'::jsonb) into v_counts
  from (select x->>'department_code' department_code,count(*) cnt from jsonb_array_elements(v_cards) x group by 1)s;
  return jsonb_set(jsonb_set(jsonb_set(v_base,'{version}','"TEST70_REAL_CHAT_WORK_V73_THREE_LANE"'::jsonb,true),'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end;
$$;

revoke all on function public.rr_real_chat_work_inbox_v73(text,text,text,integer) from public;
revoke all on function public.rr_real_chat_work_inbox_v73(text,text,text,integer) from anon;
grant execute on function public.rr_real_chat_work_inbox_v73(text,text,text,integer) to authenticated;

create or replace function public.rr_real_chat_rectification_close_form_v1(p_case_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_case public.rr_upm_rectification_cases_v9101%rowtype;
  v_profile public.rr_user_profiles%rowtype;
  v_worker uuid; v_role text;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  perform public.rr_assert_active_user_v1();
  select * into v_profile from public.rr_user_profiles p
  where p.auth_user_id=auth.uid() and coalesce(p.is_active,false)
    and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
  order by p.updated_at desc nulls last limit 1;
  if not found then raise exception 'Active profile required.'; end if;
  select * into v_case from public.rr_upm_rectification_cases_v9101 where id=p_case_id;
  if not found then raise exception 'Rectification case not found.'; end if;
  v_worker:=public.rr_upm_current_worker_id_v9112();
  v_role:=upper(replace(coalesce(v_profile.role_code,'WORKER'),' ','_'));
  if v_role not in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD')
     and v_worker is distinct from v_case.assigned_worker_id
     and v_worker is distinct from v_case.line_man_id then
    raise exception 'Rectification case permission denied.';
  end if;
  return jsonb_build_object(
    'case_id',v_case.id,'lot_no',v_case.lot_no,'colour_code',v_case.colour_code,
    'recalled_good_qty',v_case.recalled_good_qty,'original_worker_name',v_case.original_worker_name,
    'assigned_worker_name',v_case.assigned_worker_name,'status',v_case.status);
end;
$$;

revoke all on function public.rr_real_chat_rectification_close_form_v1(uuid) from public;
revoke all on function public.rr_real_chat_rectification_close_form_v1(uuid) from anon;
grant execute on function public.rr_real_chat_rectification_close_form_v1(uuid) to authenticated;

create or replace function public.rr_real_chat_close_rectification_v1(
  p_case_id uuid, p_good_qty numeric, p_damage_qty numeric default 0,
  p_alter_qty numeric default 0, p_remarks text default null
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_case public.rr_upm_rectification_cases_v9101%rowtype;
  v_profile public.rr_user_profiles%rowtype;
  v_worker uuid; v_role text;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  perform public.rr_assert_active_user_v1();
  select * into v_profile from public.rr_user_profiles p
  where p.auth_user_id=auth.uid() and coalesce(p.is_active,false)
    and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
  order by p.updated_at desc nulls last limit 1;
  if not found then raise exception 'Active profile required.'; end if;
  select * into v_case from public.rr_upm_rectification_cases_v9101 where id=p_case_id;
  if not found then raise exception 'Rectification case not found.'; end if;
  v_worker:=public.rr_upm_current_worker_id_v9112();
  v_role:=upper(replace(coalesce(v_profile.role_code,'WORKER'),' ','_'));
  if v_role not in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD')
     and v_worker is distinct from v_case.assigned_worker_id
     and v_worker is distinct from v_case.line_man_id then
    raise exception 'Only assigned worker, selected Line Man or authorised staff can close Rectification.';
  end if;
  return public.rr_upm_close_rectification_v9102(
    p_case_id,coalesce(p_good_qty,0),coalesce(p_damage_qty,0),
    coalesce(p_alter_qty,0),p_remarks);
end;
$$;

revoke all on function public.rr_real_chat_close_rectification_v1(uuid,numeric,numeric,numeric,text) from public;
revoke all on function public.rr_real_chat_close_rectification_v1(uuid,numeric,numeric,numeric,text) from anon;
grant execute on function public.rr_real_chat_close_rectification_v1(uuid,numeric,numeric,numeric,text) to authenticated;

create or replace function public.rr_real_chat_work_search_v3(
  p_status text default 'WORKING', p_search text default null,
  p_department_code text default null, p_limit integer default 500
)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_base jsonb; v_find text:=lower(trim(coalesce(p_search,'')));
  v_find_key text:=regexp_replace(lower(trim(coalesce(p_search,''))),'[^a-z0-9]','','g');
  v_cards jsonb; v_counts jsonb; v_related_lots text[]:=array[]::text[]; v_related_terms text[]:=array[]::text[];
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  v_base:=public.rr_real_chat_work_inbox_v73(p_status,null,p_department_code,least(greatest(coalesce(p_limit,500),1),500));
  if v_find='' then return v_base; end if;
  with relations as (
    select m value from jsonb_array_elements(public.rr_real_chat_media_map_v1()) m
    union all
    select jsonb_build_object('lot_no',l.lot_no,'cb_no',u.cb_code,'cb_base_no',u.cb_base_no,'cb_unit_id',l.cb_unit_id,'legacy_state',l.state)
    from public.rr_cutting_legacy_lot_link_v1 l join public.rr_cb_units u on u.id=l.cb_unit_id where l.active
  ), matched as (
    select value from relations where lower(value::text) like '%'||v_find||'%'
      or (v_find_key<>'' and regexp_replace(lower(value::text),'[^a-z0-9]','','g') like '%'||v_find_key||'%')
  )
  select coalesce(array_agg(distinct upper(trim(value->>'lot_no'))) filter(where nullif(trim(value->>'lot_no'),'') is not null),array[]::text[]),
    coalesce(array_agg(distinct lower(term)) filter(where nullif(trim(term),'') is not null),array[]::text[])
  into v_related_lots,v_related_terms from matched
  cross join lateral unnest(array[value->>'lot_no',value->>'cb_no',value->>'cb_base_no',value->>'art_no']) term;
  v_related_terms:=array_append(v_related_terms,v_find);
  select coalesce(jsonb_agg(card order by ord),'[]'::jsonb) into v_cards
  from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb)) with ordinality x(card,ord)
  where lower(card::text) like '%'||v_find||'%'
    or (v_find_key<>'' and regexp_replace(lower(card::text),'[^a-z0-9]','','g') like '%'||v_find_key||'%')
    or upper(trim(coalesce(card->>'lot_no','')))=any(v_related_lots);
  select coalesce(jsonb_object_agg(department_code,card_count),'{}'::jsonb) into v_counts
  from (select coalesce(nullif(card->>'department_code',''),'UNKNOWN') department_code,count(*) card_count from jsonb_array_elements(v_cards) x(card) group by 1)c;
  return jsonb_set(jsonb_set(jsonb_set(v_base,'{cards}',v_cards,true),'{department_counts}',v_counts,true),'{related_terms}',to_jsonb(v_related_terms),true);
end;
$$;

revoke all on function public.rr_real_chat_work_search_v3(text,text,text,integer) from public;
revoke all on function public.rr_real_chat_work_search_v3(text,text,text,integer) from anon;
grant execute on function public.rr_real_chat_work_search_v3(text,text,text,integer) to authenticated;

commit;
