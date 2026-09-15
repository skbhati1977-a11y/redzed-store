begin;
create or replace function public.rr_real_chat_work_inbox_v78(p_status text default 'WORKING',p_search text default null,p_department_code text default null,p_limit integer default 500)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_base jsonb;v_cards jsonb;v_counts jsonb;v_role text;v_dept text;v_lot jsonb;v_qty numeric;v_cap integer:=least(greatest(coalesce(p_limit,500),1),500);
begin
 if auth.uid() is null then raise exception 'Login required.'; end if;
 v_base:=public.rr_real_chat_work_inbox_v77(p_status,p_search,p_department_code,p_limit);
 if upper(coalesce(p_status,'WORKING'))<>'OPEN' then return v_base; end if;
 v_role:=upper(coalesce(v_base#>>'{actor,role}','WORKER'));
 if v_role not in('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD','PRODUCTION','CUTTING_MASTER') then return v_base; end if;
 v_cards:=coalesce(v_base->'cards','[]'::jsonb);
 for v_dept in select d from unnest(array['PRINTING','STICKER','METAL_ID','STITCHING','OVERLOCK','FOLDING','KAAJ_BUTTON','TEAK_TANKI','THREAD_CUT','QC','PRESS','PACKING'])d
  where nullif(trim(p_department_code),'')is null or public.rr_upm_core_department_v9077(d)=public.rr_upm_core_department_v9077(p_department_code)
 loop
  for v_lot in select x from jsonb_array_elements(coalesce(public.rr_upm_department_colour_due_card_v9109(v_dept)->'lots','[]'::jsonb))x
   where jsonb_array_length(coalesce(x->'assign_rows','[]'::jsonb))>0 and(coalesce(trim(p_search),'')='' or lower(x->>'lot_no')like'%'||lower(trim(p_search))||'%') limit v_cap
  loop
   if not exists(select 1 from jsonb_array_elements(v_cards)c where c->>'event_key'='UPM_DUE:'||v_dept||':'||(v_lot->>'canonical_lot_id')) then
    select coalesce(sum((r->>'qty')::numeric),0) into v_qty from jsonb_array_elements(v_lot->'assign_rows')r;
    v_cards:=v_cards||jsonb_build_array(jsonb_build_object('event_key','UPM_DUE:'||v_dept||':'||(v_lot->>'canonical_lot_id'),'source_module','UNIVERSAL_PRODUCTION','canonical_source','rr_upm_department_colour_due_card_v9109','original_record_id',v_lot->>'canonical_lot_id','canonical_lot_id',v_lot->>'canonical_lot_id','lot_no',v_lot->>'lot_no','department_code',v_dept,'department_name',v_dept,'qty',v_qty,'source_status','READY_TO_ASSIGN','chat_status','OPEN','work_category','READY_TO_ASSIGN','event_at',coalesce((v_lot#>>'{assign_rows,0,due_since}')::timestamptz,now()),'actions',jsonb_build_array(jsonb_build_object('code','ASSIGN_WORKER','label','ASSIGN WORKER','href','real-department-lite-v9127.html?mode=TEST&from=TEST70_REAL_CHAT&rrMode=ASSIGN&rrOpenAssign='||(v_lot->>'lot_no')||'&dept='||v_dept,'engine','rr_upm_assign_work_v9107')),'visible_department_codes',jsonb_build_array(v_dept)));
   end if;
  end loop;
 end loop;
 select coalesce(jsonb_object_agg(department_code,cnt),'{}'::jsonb)into v_counts from(select coalesce(nullif(c->>'department_code',''),'UNKNOWN')department_code,count(*)cnt from jsonb_array_elements(v_cards)c group by 1)s;
 return jsonb_set(jsonb_set(jsonb_set(v_base,'{version}','"TEST70_REAL_CHAT_WORK_V78_DEPARTMENT_DUE_OPEN"'::jsonb,true),'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end;$$;
revoke all on function public.rr_real_chat_work_inbox_v78(text,text,text,integer)from public;
revoke all on function public.rr_real_chat_work_inbox_v78(text,text,text,integer)from anon;
grant execute on function public.rr_real_chat_work_inbox_v78(text,text,text,integer)to authenticated;
create or replace function public.rr_real_chat_work_search_v5(p_status text default 'WORKING',p_search text default null,p_department_code text default null,p_limit integer default 500)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_base jsonb;v_find text:=lower(trim(coalesce(p_search,'')));v_key text:=regexp_replace(lower(trim(coalesce(p_search,''))),'[^a-z0-9]','','g');v_cards jsonb;v_counts jsonb;
begin
 if auth.uid() is null then raise exception 'Login required.'; end if;v_base:=public.rr_real_chat_work_inbox_v78(p_status,null,p_department_code,p_limit);if v_find=''then return v_base;end if;
 select coalesce(jsonb_agg(card order by ord),'[]'::jsonb)into v_cards from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb))with ordinality x(card,ord)where lower(card::text)like'%'||v_find||'%'or(v_key<>''and regexp_replace(lower(card::text),'[^a-z0-9]','','g')like'%'||v_key||'%');
 select coalesce(jsonb_object_agg(department_code,card_count),'{}'::jsonb)into v_counts from(select coalesce(nullif(card->>'department_code',''),'UNKNOWN')department_code,count(*)card_count from jsonb_array_elements(v_cards)x(card)group by 1)c;
 return jsonb_set(jsonb_set(v_base,'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end;$$;
revoke all on function public.rr_real_chat_work_search_v5(text,text,text,integer)from public;
revoke all on function public.rr_real_chat_work_search_v5(text,text,text,integer)from anon;
grant execute on function public.rr_real_chat_work_search_v5(text,text,text,integer)to authenticated;
commit;
