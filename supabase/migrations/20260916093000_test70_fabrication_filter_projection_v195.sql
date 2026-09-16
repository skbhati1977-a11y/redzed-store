-- TEST70 V195: build the virtual Fabrication projection before applying its group filter.
begin;
create or replace function public.rr_real_chat_work_search_v10(p_status text default 'WORKING',p_search text default null,p_department_code text default null,p_limit integer default 500)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare v_base jsonb;v_find text:=lower(trim(coalesce(p_search,'')));v_key text:=regexp_replace(lower(trim(coalesce(p_search,''))),'[^a-z0-9]','','g');v_cards jsonb;v_counts jsonb;v_fabrication boolean:=upper(trim(coalesce(p_department_code,'')))='FABRICATION';
begin
 if auth.uid()is null then raise exception 'Login required.';end if;
 v_base:=public.rr_real_chat_work_inbox_v83(p_status,null,case when v_fabrication then null else p_department_code end,p_limit);
 select coalesce(jsonb_agg(card order by ord),'[]'::jsonb)into v_cards
 from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb))with ordinality x(card,ord)
 where (not v_fabrication or upper(coalesce(card->>'department_code',''))='FABRICATION')
 and (v_find='' or lower(card::text)like'%'||v_find||'%'or(v_key<>''and regexp_replace(lower(card::text),'[^a-z0-9]','','g')like'%'||v_key||'%'));
 select coalesce(jsonb_object_agg(department_code,card_count),'{}'::jsonb)into v_counts from(select coalesce(nullif(card->>'department_code',''),'UNKNOWN')department_code,count(*)card_count from jsonb_array_elements(v_cards)x(card)group by 1)c;
 return jsonb_set(jsonb_set(v_base,'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end $function$;
revoke all on function public.rr_real_chat_work_search_v10(text,text,text,integer)from public,anon;grant execute on function public.rr_real_chat_work_search_v10(text,text,text,integer)to authenticated;
commit;
