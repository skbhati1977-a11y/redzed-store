begin;

-- Rebind legacy active journeys to the current unified worker identities.
-- Names are already frozen on each journey; only an exact active directory-name match is used.
update public.rr_upm_alter_journey_v740 j set
  enrolled_lm_id=coalesce((select d.worker_id from public.rr_worker_directory_unified_v1 d where lower(trim(d.worker_name))=lower(trim(j.enrolled_lm_name)) order by (d.linked_auth_user_id is not null) desc limit 1),j.enrolled_lm_id),
  cutting_master_id=coalesce((select d.worker_id from public.rr_worker_directory_unified_v1 d where lower(trim(d.worker_name))=lower(trim(j.cutting_master_name)) order by (d.linked_auth_user_id is not null) desc limit 1),j.cutting_master_id),
  karigar_id=coalesce((select d.worker_id from public.rr_worker_directory_unified_v1 d where lower(trim(d.worker_name))=lower(trim(j.karigar_name)) order by (d.linked_auth_user_id is not null) desc limit 1),j.karigar_id),
  responsible_id=coalesce((select d.worker_id from public.rr_worker_directory_unified_v1 d where lower(trim(d.worker_name))=lower(trim(j.responsible_name)) order by (d.linked_auth_user_id is not null) desc limit 1),j.responsible_id),
  updated_at=now(),route_version='V124_REAL_CHAT_IDENTITY_REBOUND'
where j.stage not like 'CLOSED%';

create or replace function public.rr_real_chat_alter_action_v1(
  p_action text, p_journey_id uuid, p_qty numeric default null, p_remarks text default null
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_j public.rr_upm_alter_journey_v740%rowtype;
  v_action text:=upper(trim(coalesce(p_action,'')));
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  perform public.rr_assert_active_user_v1();
  select * into v_j from public.rr_upm_alter_journey_v740 where id=p_journey_id;
  if not found then raise exception 'Alter journey not found.'; end if;
  if v_action='LM_ACCEPT' then
    return public.rr_upm_accept_alter_v9114(p_journey_id,p_remarks);
  end if;
  return public.rr_upm_alter_transition_v771(
    v_action,
    jsonb_build_array(jsonb_build_object('journey_id',p_journey_id,'qty',coalesce(p_qty,v_j.open_qty))),
    p_remarks
  );
end;
$$;
revoke all on function public.rr_real_chat_alter_action_v1(text,uuid,numeric,text) from public;
revoke all on function public.rr_real_chat_alter_action_v1(text,uuid,numeric,text) from anon;
grant execute on function public.rr_real_chat_alter_action_v1(text,uuid,numeric,text) to authenticated;

create or replace function public.rr_real_chat_work_inbox_v74(
  p_status text default 'WORKING', p_search text default null,
  p_department_code text default null, p_limit integer default 500
)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_base jsonb; v_cards jsonb:='[]'::jsonb; v_card jsonb; v_actions jsonb;
  v_j public.rr_upm_alter_journey_v740%rowtype;
  v_role text; v_worker uuid; v_stage text; v_code text; v_label text; v_allowed boolean;
  v_origin text; v_current text; v_home text; v_visible_depts jsonb; v_visible_workers jsonb;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  v_base:=public.rr_real_chat_work_inbox_v73(p_status,p_search,p_department_code,p_limit);
  v_role:=upper(coalesce(v_base#>>'{actor,role}','WORKER'));
  v_worker:=nullif(v_base#>>'{actor,worker_id}','')::uuid;
  v_home:=public.rr_upm_core_department_v9077(v_base#>>'{actor,department_code}');

  -- V73 inherited the legacy origin/holder visibility rule. Add every active journey
  -- where the signed-in person is a mapped participant or current department member.
  if upper(coalesce(p_status,'WORKING'))='WORKING' then
    for v_j in select j.* from public.rr_upm_alter_journey_v740 j
      where j.stage not like 'CLOSED%' and j.open_qty>0
        and (v_role in ('OWNER','SUPER_ADMIN','ADMIN') or v_worker in (j.responsible_id,j.karigar_id,j.enrolled_lm_id,j.cutting_master_id)
          or public.rr_upm_core_department_v9077(j.origin_department_code)=v_home
          or public.rr_upm_core_department_v9077(j.responsible_department_code)=v_home)
        and (coalesce(trim(p_search),'')='' or lower(concat_ws(' ',j.lot_no,j.colour_code,j.colour_name,j.size_code,j.responsible_name,j.enrolled_lm_name,j.cutting_master_name,j.karigar_name,j.stage)) like '%'||lower(trim(p_search))||'%')
    loop
      if not exists(select 1 from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb)) c where c->>'event_key'='UPM_ALTER:'||v_j.id) then
        v_base:=jsonb_set(v_base,'{cards}',coalesce(v_base->'cards','[]'::jsonb)||jsonb_build_array(jsonb_build_object(
          'event_key','UPM_ALTER:'||v_j.id,'source_module','UPM_ALTER_JOURNEY','original_record_id',v_j.id,
          'canonical_lot_id',v_j.canonical_lot_id,'lot_no',v_j.lot_no,
          'department_code',public.rr_upm_core_department_v9077(v_j.origin_department_code),
          'department_name',public.rr_upm_core_department_v9077(v_j.origin_department_code),
          'colour_code',v_j.colour_code,'colour_name',v_j.colour_name,'size_code',v_j.size_code,
          'worker_id',v_j.responsible_id,'worker_name',v_j.responsible_name,'qty',v_j.open_qty,
          'source_status',v_j.stage,'chat_status','WORKING','event_at',v_j.updated_at,
          'art_images',coalesce(v_j.evidence_urls,'[]'::jsonb),'actions','[]'::jsonb,
          'canonical_source','rr_upm_alter_journey_v740')),true);
      end if;
    end loop;
  end if;

  for v_card in select value from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb)) loop
    if v_card->>'canonical_source'='rr_upm_alter_journey_v740'
       and nullif(v_card->>'original_record_id','') is not null then
      select * into v_j from public.rr_upm_alter_journey_v740
      where id=(v_card->>'original_record_id')::uuid;
      if found then
        v_stage:=upper(coalesce(v_j.stage,''));
        v_origin:=public.rr_upm_core_department_v9077(v_j.origin_department_code);
        v_current:=public.rr_upm_core_department_v9077(coalesce(nullif(v_j.responsible_department_code,''),v_j.origin_department_code));
        if v_stage in ('LM_ALTER_PENDING','CM_REMAKE_READY') then v_current:='CUTTING'; end if;
        select coalesce(jsonb_agg(distinct x),'[]'::jsonb) into v_visible_depts
        from unnest(array[v_origin,v_current]) x where x is not null;
        select coalesce(jsonb_agg(distinct x),'[]'::jsonb) into v_visible_workers
        from unnest(array[v_j.responsible_id,v_j.karigar_id,v_j.enrolled_lm_id,v_j.cutting_master_id]) x where x is not null;
        v_code:=null; v_label:=null; v_allowed:=false;
        if v_stage='ALTER_LM_ACCEPT_PENDING' then
          v_code:='LM_ACCEPT'; v_label:='ACCEPT ALTER · TAKE CUSTODY';
          v_allowed:=v_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER') or v_worker=v_j.enrolled_lm_id;
        elsif v_stage='LM_ALTER_PENDING' then
          v_code:='REMAKE_ISSUE'; v_label:='SEND TO CUTTING MASTER';
          v_allowed:=v_role in ('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER') or v_worker=v_j.cutting_master_id;
        elsif v_stage='CM_REMAKE_READY' then
          v_code:='RECEIVE_FROM_MASTER'; v_label:='RECEIVE FROM CUTTING MASTER';
          v_allowed:=v_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN') or v_worker=v_j.enrolled_lm_id;
        elsif v_stage='LM_DELIVERY_PENDING' then
          v_code:='DELIVER_TO_KARIGAR'; v_label:='DELIVER TO KARIGAR';
          v_allowed:=v_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN') or v_worker=v_j.enrolled_lm_id;
        elsif v_stage='KARIGAR_REMAKE_PENDING' then
          v_code:='KARIGAR_SUBMIT_GOOD'; v_label:='SUBMIT ALTER AS GOOD';
          v_allowed:=v_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER')
            or v_worker in (v_j.responsible_id,v_j.karigar_id,v_j.enrolled_lm_id);
        end if;
        v_actions:=case when v_allowed and v_code is not null then jsonb_build_array(jsonb_build_object(
          'code',v_code,'label',v_label,'inline_alter',true,'journey_id',v_j.id,
          'qty',v_j.open_qty,'engine',case when v_code='LM_ACCEPT' then 'rr_upm_accept_alter_v9114' else 'rr_upm_alter_transition_v771' end
        )) else '[]'::jsonb end;
        v_card:=v_card||jsonb_build_object(
          'work_category','ALTER','department_code',v_origin,'current_department_code',v_current,
          'visible_department_codes',v_visible_depts,'visible_worker_ids',v_visible_workers,
          'worker_id',v_j.responsible_id,'worker_name',v_j.responsible_name,
          'journey_id',v_j.id,'journey_stage',v_stage,'actions',v_actions,
          'action_waiting',case when v_code is not null and not v_allowed then 'WAITING FOR CURRENT RESPONSIBLE PERSON' else null end,
          'requires_action',false
        );
      end if;
    end if;
    v_cards:=v_cards||jsonb_build_array(v_card);
  end loop;
  return jsonb_set(jsonb_set(v_base,'{version}','"TEST70_REAL_CHAT_WORK_V74_ALTER_INLINE"'::jsonb,true),'{cards}',v_cards,true);
end;
$$;
revoke all on function public.rr_real_chat_work_inbox_v74(text,text,text,integer) from public;
revoke all on function public.rr_real_chat_work_inbox_v74(text,text,text,integer) from anon;
grant execute on function public.rr_real_chat_work_inbox_v74(text,text,text,integer) to authenticated;

create or replace function public.rr_real_chat_work_search_v4(
  p_status text default 'WORKING', p_search text default null,
  p_department_code text default null, p_limit integer default 500
)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_base jsonb; v_find text:=lower(trim(coalesce(p_search,''))); v_cards jsonb; v_counts jsonb;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  v_base:=public.rr_real_chat_work_inbox_v74(p_status,null,p_department_code,p_limit);
  if v_find='' then return v_base; end if;
  select coalesce(jsonb_agg(card order by ord),'[]'::jsonb) into v_cards
  from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb)) with ordinality x(card,ord)
  where lower(card::text) like '%'||v_find||'%'
     or regexp_replace(lower(card::text),'[^a-z0-9]','','g') like '%'||regexp_replace(v_find,'[^a-z0-9]','','g')||'%';
  select coalesce(jsonb_object_agg(department_code,card_count),'{}'::jsonb) into v_counts
  from (select coalesce(nullif(card->>'department_code',''),'UNKNOWN') department_code,count(*) card_count
        from jsonb_array_elements(v_cards) x(card) group by 1)c;
  return jsonb_set(jsonb_set(v_base,'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end;
$$;
revoke all on function public.rr_real_chat_work_search_v4(text,text,text,integer) from public;
revoke all on function public.rr_real_chat_work_search_v4(text,text,text,integer) from anon;
grant execute on function public.rr_real_chat_work_search_v4(text,text,text,integer) to authenticated;

commit;
