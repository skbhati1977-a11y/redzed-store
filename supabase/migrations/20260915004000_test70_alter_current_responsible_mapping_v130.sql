begin;
create or replace function public.rr_real_chat_work_inbox_v77(p_status text default 'WORKING',p_search text default null,p_department_code text default null,p_limit integer default 500)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_base jsonb;v_cards jsonb:='[]'::jsonb;v_card jsonb;v_j public.rr_upm_alter_journey_v740%rowtype;v_target uuid;v_target_name text;v_current_dept text;v_counts jsonb;
begin
 if auth.uid() is null then raise exception 'Login required.'; end if;
 v_base:=public.rr_real_chat_work_inbox_v76(p_status,p_search,p_department_code,p_limit);
 for v_card in select value from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb)) loop
  if upper(coalesce(p_status,'WORKING'))='WORKING' and v_card->>'canonical_source'='rr_upm_alter_journey_v740' and nullif(v_card->>'original_record_id','') is not null then
   select * into v_j from public.rr_upm_alter_journey_v740 where id=(v_card->>'original_record_id')::uuid;
   if found then
    v_target:=case upper(coalesce(v_j.stage,'')) when 'ALTER_LM_ACCEPT_PENDING' then v_j.enrolled_lm_id when 'LM_ALTER_PENDING' then v_j.cutting_master_id when 'CM_REMAKE_READY' then v_j.enrolled_lm_id when 'LM_DELIVERY_PENDING' then v_j.enrolled_lm_id when 'KARIGAR_REMAKE_PENDING' then coalesce(v_j.karigar_id,v_j.responsible_id) else v_j.responsible_id end;
    v_target_name:=case upper(coalesce(v_j.stage,'')) when 'ALTER_LM_ACCEPT_PENDING' then v_j.enrolled_lm_name when 'LM_ALTER_PENDING' then v_j.cutting_master_name when 'CM_REMAKE_READY' then v_j.enrolled_lm_name when 'LM_DELIVERY_PENDING' then v_j.enrolled_lm_name when 'KARIGAR_REMAKE_PENDING' then coalesce(v_j.karigar_name,v_j.responsible_name) else v_j.responsible_name end;
    v_current_dept:=case when upper(coalesce(v_j.stage,''))='LM_ALTER_PENDING' then 'CUTTING' else public.rr_upm_core_department_v9077(coalesce(v_j.responsible_department_code,v_j.origin_department_code)) end;
    v_card:=v_card||jsonb_build_object('worker_id',v_target,'worker_name',v_target_name,'visible_worker_ids',case when v_target is null then '[]'::jsonb else jsonb_build_array(v_target) end,'current_department_code',v_current_dept,'action_target_worker_id',v_target,'origin_worker_id',coalesce(v_j.karigar_id,v_j.responsible_id),'origin_worker_name',coalesce(v_j.karigar_name,v_j.responsible_name));
   end if;
  end if;
  v_cards:=v_cards||jsonb_build_array(v_card);
 end loop;
 select coalesce(jsonb_object_agg(department_code,cnt),'{}'::jsonb) into v_counts from(select coalesce(nullif(c->>'department_code',''),'UNKNOWN')department_code,count(*)cnt from jsonb_array_elements(v_cards)c group by 1)s;
 return jsonb_set(jsonb_set(jsonb_set(v_base,'{version}','"TEST70_REAL_CHAT_WORK_V77_CURRENT_RESPONSIBLE"'::jsonb,true),'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end;$$;
revoke all on function public.rr_real_chat_work_inbox_v77(text,text,text,integer) from public;
revoke all on function public.rr_real_chat_work_inbox_v77(text,text,text,integer) from anon;
grant execute on function public.rr_real_chat_work_inbox_v77(text,text,text,integer) to authenticated;
create or replace function public.rr_real_chat_work_search_v5(p_status text default 'WORKING',p_search text default null,p_department_code text default null,p_limit integer default 500)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_base jsonb;v_find text:=lower(trim(coalesce(p_search,'')));v_key text:=regexp_replace(lower(trim(coalesce(p_search,''))),'[^a-z0-9]','','g');v_cards jsonb;v_counts jsonb;
begin
 if auth.uid() is null then raise exception 'Login required.'; end if;
 v_base:=public.rr_real_chat_work_inbox_v77(p_status,null,p_department_code,p_limit);
 if v_find='' then return v_base; end if;
 select coalesce(jsonb_agg(card order by ord),'[]'::jsonb) into v_cards from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb))with ordinality x(card,ord) where lower(card::text)like'%'||v_find||'%' or(v_key<>'' and regexp_replace(lower(card::text),'[^a-z0-9]','','g')like'%'||v_key||'%');
 select coalesce(jsonb_object_agg(department_code,card_count),'{}'::jsonb) into v_counts from(select coalesce(nullif(card->>'department_code',''),'UNKNOWN')department_code,count(*)card_count from jsonb_array_elements(v_cards)x(card)group by 1)c;
 return jsonb_set(jsonb_set(v_base,'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end;$$;
revoke all on function public.rr_real_chat_work_search_v5(text,text,text,integer) from public;
revoke all on function public.rr_real_chat_work_search_v5(text,text,text,integer) from anon;
grant execute on function public.rr_real_chat_work_search_v5(text,text,text,integer) to authenticated;
commit;
