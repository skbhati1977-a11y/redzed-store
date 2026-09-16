-- TEST70 V193: canonical App Ready-to-Assign mirrored to Lineman chats.
begin;
create or replace function public.rr_real_chat_work_inbox_v82(p_status text default 'WORKING',p_search text default null,p_department_code text default null,p_limit integer default 500)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare v_base jsonb;v_cards jsonb;v_profile public.rr_user_profiles%rowtype;v_actor_worker uuid;v_role text;v_home text;
begin
 if auth.uid() is null then raise exception 'Login required.';end if;
 select * into v_profile from public.rr_user_profiles where auth_user_id=auth.uid() and is_active and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' order by updated_at desc nulls last limit 1;
 if not found then raise exception 'Active User Directory profile required.';end if;
 v_role:=upper(coalesce(v_profile.role_code,'WORKER'));v_home:=public.rr_upm_core_department_v9077(v_profile.department_code);v_actor_worker:=public.rr_upm_current_worker_id_v9112();
 v_base:=public.rr_real_chat_work_inbox_v81(p_status,p_search,p_department_code,p_limit);
 select coalesce(jsonb_agg(case
  when v_role in ('OWNER','SUPER_ADMIN','ADMIN') then card
  when v_role='MANAGER' and v_home='FABRICATION' and lower(trim(coalesce(v_profile.full_name,'')))='nasim' then card
  when v_role in ('LINE_MANAGER','LINE_MAN') and exists(select 1 from jsonb_array_elements(coalesce(card->'actions','[]'::jsonb))a where upper(coalesce(a->>'code',''))='ASSIGN_WORKER') then card
  when v_actor_worker is not null and (nullif(card->>'worker_id','')=v_actor_worker::text or exists(select 1 from jsonb_array_elements_text(case when jsonb_typeof(card->'visible_worker_ids')='array' then card->'visible_worker_ids' else '[]'::jsonb end)wid where wid=v_actor_worker::text)) then card
  when v_role in ('MANAGER','DEPARTMENT_HEAD','CUTTING_MASTER') and v_home=public.rr_upm_core_department_v9077(coalesce(nullif(card->>'source_department_code',''),card->>'department_code')) then card
  else (card-'action_waiting')||jsonb_build_object('actions','[]'::jsonb,'requires_action',false,'staff_view_only',true,'authorization_note','Department STAFF membership is view-only') end order by ord),'[]'::jsonb) into v_cards
 from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb))with ordinality x(card,ord);
 return jsonb_set(jsonb_set(v_base,'{version}',to_jsonb('TEST70_REAL_CHAT_WORK_V82_LINEMAN_ASSIGN_AUTH'::text),true),'{cards}',v_cards,true);
end $function$;
revoke all on function public.rr_real_chat_work_inbox_v82(text,text,text,integer) from public,anon;grant execute on function public.rr_real_chat_work_inbox_v82(text,text,text,integer) to authenticated;

create or replace function public.rr_real_chat_work_inbox_v83(p_status text default 'WORKING',p_search text default null,p_department_code text default null,p_limit integer default 500)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare v_base jsonb;v_cards jsonb;v_counts jsonb;v_role text;v_lineman_ids jsonb;r record;v_projection jsonb;
begin
 if auth.uid() is null then raise exception 'Login required.';end if;
 v_base:=public.rr_real_chat_work_inbox_v82(p_status,p_search,p_department_code,p_limit);v_cards:=coalesce(v_base->'cards','[]'::jsonb);v_role:=upper(coalesce(v_base#>>'{actor,role}','WORKER'));
 select coalesce(jsonb_agg(distinct p.auth_user_id),'[]'::jsonb) into v_lineman_ids from public.rr_user_profiles p where p.is_active and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE' and upper(coalesce(p.role_code,''))in('LINE_MANAGER','LINE_MAN') and public.rr_upm_core_department_v9077(p.department_code)='FABRICATION';
 if upper(coalesce(p_status,'WORKING'))='OPEN' and v_role in('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN') and(nullif(trim(p_department_code),'')is null or upper(trim(p_department_code))='FABRICATION')then
  for r in select distinct on(coalesce(card->>'canonical_lot_id',card->>'lot_no'),card->>'department_code')card from jsonb_array_elements(v_cards)card where upper(coalesce(card->>'department_code',''))<>'FABRICATION' and exists(select 1 from jsonb_array_elements(coalesce(card->'actions','[]'::jsonb))a where upper(coalesce(a->>'code',''))='ASSIGN_WORKER') order by coalesce(card->>'canonical_lot_id',card->>'lot_no'),card->>'department_code',coalesce(card->>'event_at','')desc
  loop
   v_projection:=r.card||jsonb_build_object('event_key','UPM_FABRICATION_ASSIGN:'||coalesce(r.card->>'canonical_lot_id',r.card->>'lot_no')||':'||r.card->>'department_code','department_code','FABRICATION','department_name','Fabrication / Line Man','source_department_code',r.card->>'department_code','visible_department_codes',jsonb_build_array('FABRICATION'),'worker_id',null,'worker_name','Shared Lineman Queue','visible_worker_ids',v_lineman_ids,'work_category','READY_TO_ASSIGN','message','Ready to Assign · '||public.rr_costing_department_display_v760(r.card->>'department_code'),'group_only',false,'canonical_source','rr_upm_ready_to_assign_v9107');
   v_cards:=v_cards||jsonb_build_array(v_projection);
  end loop;
 end if;
 if upper(trim(coalesce(p_department_code,'')))='FABRICATION'then select coalesce(jsonb_agg(value),'[]'::jsonb)into v_cards from jsonb_array_elements(v_cards)where upper(coalesce(value->>'department_code',''))='FABRICATION';end if;
 select coalesce(jsonb_object_agg(department_code,cnt),'{}'::jsonb)into v_counts from(select coalesce(nullif(x->>'department_code',''),'UNKNOWN')department_code,count(*)cnt from jsonb_array_elements(v_cards)x group by 1)s;
 return jsonb_set(jsonb_set(jsonb_set(v_base,'{version}',to_jsonb('TEST70_REAL_CHAT_WORK_V83_LINEMAN_READY_ASSIGN'::text),true),'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end $function$;
revoke all on function public.rr_real_chat_work_inbox_v83(text,text,text,integer)from public,anon;grant execute on function public.rr_real_chat_work_inbox_v83(text,text,text,integer)to authenticated;

create or replace function public.rr_real_chat_work_search_v10(p_status text default 'WORKING',p_search text default null,p_department_code text default null,p_limit integer default 500)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare v_base jsonb;v_find text:=lower(trim(coalesce(p_search,'')));v_key text:=regexp_replace(lower(trim(coalesce(p_search,''))),'[^a-z0-9]','','g');v_cards jsonb;v_counts jsonb;
begin
 if auth.uid()is null then raise exception 'Login required.';end if;v_base:=public.rr_real_chat_work_inbox_v83(p_status,null,p_department_code,p_limit);if v_find=''then return v_base;end if;
 select coalesce(jsonb_agg(card order by ord),'[]'::jsonb)into v_cards from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb))with ordinality x(card,ord)where lower(card::text)like'%'||v_find||'%'or(v_key<>''and regexp_replace(lower(card::text),'[^a-z0-9]','','g')like'%'||v_key||'%');
 select coalesce(jsonb_object_agg(department_code,card_count),'{}'::jsonb)into v_counts from(select coalesce(nullif(card->>'department_code',''),'UNKNOWN')department_code,count(*)card_count from jsonb_array_elements(v_cards)x(card)group by 1)c;
 return jsonb_set(jsonb_set(v_base,'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end $function$;
revoke all on function public.rr_real_chat_work_search_v10(text,text,text,integer)from public,anon;grant execute on function public.rr_real_chat_work_search_v10(text,text,text,integer)to authenticated;
commit;
