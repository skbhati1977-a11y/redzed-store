begin;

-- TEST70 lifecycle corrections found in the Print-to-Packing audit.
create or replace function public.rr_real_chat_work_inbox_v72(
  p_status text default 'WORKING',
  p_search text default null,
  p_department_code text default null,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_base jsonb;
  v_cards jsonb;
  v_counts jsonb;
  v_card jsonb;
  v_actions jsonb;
  v_state text:=upper(trim(coalesce(p_status,'WORKING')));
  v_role text;
  v_worker uuid;
  v_home text;
  v_global boolean;
  v_staff boolean;
  v_assignment public.rr_upm_work_assignments_v8%rowtype;
  v_dept text;
  v_link text;
  v_cap integer:=least(greatest(coalesce(p_limit,200),1),500);
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  v_base:=public.rr_real_chat_work_inbox_v71(p_status,p_search,p_department_code,v_cap);
  v_cards:=coalesce(v_base->'cards','[]'::jsonb);
  v_role:=upper(coalesce(v_base#>>'{actor,role}','WORKER'));
  v_worker:=nullif(v_base#>>'{actor,worker_id}','')::uuid;
  v_home:=public.rr_upm_core_department_v9077(v_base#>>'{actor,department_code}');
  v_global:=v_role in ('OWNER','SUPER_ADMIN','ADMIN');
  v_staff:=v_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD','PRODUCTION','CUTTING_MASTER');

  -- Owner and Super Admin must have the same canonical assignment entry point as staff.
  if v_state='OPEN' and v_role in ('OWNER','SUPER_ADMIN') then
    v_cards:='[]'::jsonb;
    for v_card in select value from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb)) loop
      v_actions:=coalesce(v_card->'actions','[]'::jsonb);
      if not exists(select 1 from jsonb_array_elements(v_actions) a where a->>'code'='ASSIGN_WORKER') then
        v_dept:=v_card->>'department_code';
        v_link:='real-universal-production-v770-v9059.html?mode=TEST&dept='||v_dept||'&from=TEST70_REAL_CHAT&rrMode=ASSIGN';
        v_actions:=v_actions||jsonb_build_array(jsonb_build_object(
          'code','ASSIGN_WORKER','label','ASSIGN WORKER','href',v_link,
          'engine','rr_upm_ready_to_assign_v9107'));
      end if;
      v_cards:=v_cards||jsonb_build_array(jsonb_set(v_card,'{actions}',v_actions,true));
    end loop;
  end if;

  -- Every active alter/remake custody card must lead to the current journey action.
  if v_state='WORKING' then
    v_base:=jsonb_set(v_base,'{cards}',v_cards,true);
    v_cards:='[]'::jsonb;
    for v_card in select value from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb)) loop
      v_actions:=coalesce(v_card->'actions','[]'::jsonb);
      if v_card->>'canonical_source'='rr_upm_alter_journey_v740' and jsonb_array_length(v_actions)=0 then
        v_dept:=v_card->>'department_code';
        v_link:='real-universal-production-v770-v9059.html?mode=TEST&dept='||v_dept||'&from=TEST70_REAL_CHAT';
        if upper(coalesce(v_card->>'source_status',''))='ALTER_LM_ACCEPT_PENDING' then
          v_actions:=jsonb_build_array(jsonb_build_object(
            'code','LM_ACCEPT','label','ACCEPT ALTER · LM','href',v_link,
            'engine','rr_upm_accept_alter_v9114'));
        else
          v_actions:=jsonb_build_array(jsonb_build_object(
            'code','OPEN_ALTER_JOURNEY','label','OPEN ALTER JOURNEY','href',v_link,
            'engine','rr_upm_alter_custody_v9114'));
        end if;
      end if;
      v_cards:=v_cards||jsonb_build_array(jsonb_set(v_card,'{actions}',v_actions,true));
    end loop;
  end if;

  -- RELEASED means this assignment was handed off. Keep it in immutable CLOSE history.
  if v_state='CLOSE' and jsonb_array_length(v_cards)<v_cap then
    for v_assignment in
      select a.* from public.rr_upm_work_assignments_v8 a
      where a.status='RELEASED'
        and (nullif(trim(p_department_code),'') is null
          or public.rr_upm_core_department_v9077(a.department_code)=public.rr_upm_core_department_v9077(p_department_code))
        and (v_global or a.worker_id=v_worker or public.rr_upm_core_department_v9077(a.department_code)=v_home)
        and (v_staff or a.worker_id=v_worker)
        and (coalesce(trim(p_search),'')='' or lower(concat_ws(' ',a.lot_no,a.colour_code,a.colour_name,a.worker_name_snapshot,a.department_code,a.status)) like '%'||lower(trim(p_search))||'%')
      order by coalesce(a.completed_at,a.updated_at,a.assigned_at) desc
      limit greatest(v_cap-jsonb_array_length(v_cards),0)
    loop
      v_dept:=public.rr_upm_core_department_v9077(v_assignment.department_code);
      v_cards:=v_cards||jsonb_build_array(jsonb_build_object(
        'event_key','UPM_ASSIGNMENT:'||v_assignment.id,
        'source_module','UNIVERSAL_PRODUCTION','original_record_id',v_assignment.id,
        'canonical_lot_id',v_assignment.canonical_lot_id,'lot_no',v_assignment.lot_no,
        'department_code',v_dept,'department_name',v_dept,
        'colour_code',v_assignment.colour_code,'colour_name',v_assignment.colour_name,
        'worker_id',v_assignment.worker_id,'worker_name',v_assignment.worker_name_snapshot,
        'qty',greatest(coalesce(v_assignment.inbound_qty,0),coalesce(v_assignment.assigned_qty,0)),
        'actual_rate',v_assignment.actual_rate,'source_status','RELEASED','chat_status','CLOSE',
        'sender_user_id',v_assignment.assigned_by,'sender_name',v_assignment.assigned_by_name,
        'event_at',coalesce(v_assignment.completed_at,v_assignment.updated_at,v_assignment.assigned_at),
        'art_images','[]'::jsonb,'print_images','[]'::jsonb,'sticker_images','[]'::jsonb,
        'metal_id_images','[]'::jsonb,'actions','[]'::jsonb,
        'canonical_source','rr_upm_work_assignments_v8'));
    end loop;
  end if;

  select coalesce(jsonb_object_agg(department_code,cnt),'{}'::jsonb) into v_counts
  from (select x->>'department_code' department_code,count(*) cnt from jsonb_array_elements(v_cards) x group by 1) s;
  return jsonb_set(jsonb_set(jsonb_set(v_base,'{version}','"TEST70_REAL_CHAT_WORK_V72_AUDITED"'::jsonb,true),'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end;
$$;

revoke all on function public.rr_real_chat_work_inbox_v72(text,text,text,integer) from public;
grant execute on function public.rr_real_chat_work_inbox_v72(text,text,text,integer) to authenticated;

create or replace function public.rr_real_chat_work_search_v2(
  p_status text default 'WORKING', p_search text default null,
  p_department_code text default null, p_limit integer default 500
)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_base jsonb; v_find text:=lower(trim(coalesce(p_search,'')));
  v_find_key text:=regexp_replace(lower(trim(coalesce(p_search,''))),'[^a-z0-9]','','g');
  v_cards jsonb; v_counts jsonb; v_related_lots text[]:=array[]::text[];
  v_related_terms text[]:=array[]::text[];
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  v_base:=public.rr_real_chat_work_inbox_v72(p_status,null,p_department_code,least(greatest(coalesce(p_limit,500),1),500));
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

revoke all on function public.rr_real_chat_work_search_v2(text,text,text,integer) from public;
grant execute on function public.rr_real_chat_work_search_v2(text,text,text,integer) to authenticated;

-- Canonical factory order. Sticker and Metal ID remain optional pre-production branches.
update public.rr_upm_departments set sequence_no=50 where department_code='STITCHING';
update public.rr_upm_departments set sequence_no=51 where department_code='OVERLOCK';
update public.rr_upm_departments set sequence_no=52 where department_code='FOLDING';
update public.rr_upm_departments set sequence_no=53 where department_code='KAAJ_BUTTON';
update public.rr_upm_departments set sequence_no=54 where department_code='TEAK_TANKI';
update public.rr_upm_departments set sequence_no=55 where department_code='THREAD_CUT';
update public.rr_upm_departments set sequence_no=56 where department_code='QC';
update public.rr_upm_departments set sequence_no=57 where department_code='PRESS';
update public.rr_upm_departments set sequence_no=58 where department_code='PACKING';

commit;
