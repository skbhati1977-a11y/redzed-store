-- TEST70 V198: never leave a Lineman WORKING custody card visually actionless.
begin;
create or replace function public.rr_real_chat_work_search_v11(p_status text default 'WORKING',p_search text default null,p_department_code text default null,p_limit integer default 500)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare v_base jsonb;v_cards jsonb;
begin
 if auth.uid()is null then raise exception 'Login required.';end if;
 v_base:=public.rr_real_chat_work_search_v10(p_status,p_search,p_department_code,p_limit);
 select coalesce(jsonb_agg(case
  when upper(coalesce(card->>'work_category',''))='CUSTODY_HANDOVER'
   and upper(coalesce(card->>'source_status',''))in('PENDING','DISPUTED')
   and jsonb_array_length(coalesce(card->'actions','[]'::jsonb))=0
  then card||jsonb_build_object('action_waiting','WAITING FOR WORKER RECEIPT','requires_action',false)
  else card end order by ord),'[]'::jsonb)into v_cards
 from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb))with ordinality x(card,ord);
 return jsonb_set(jsonb_set(v_base,'{version}',to_jsonb('TEST70_REAL_CHAT_WORK_V11_WAITING_ACTION_V198'::text),true),'{cards}',v_cards,true);
end $function$;
revoke all on function public.rr_real_chat_work_search_v11(text,text,text,integer)from public,anon;grant execute on function public.rr_real_chat_work_search_v11(text,text,text,integer)to authenticated;
commit;
