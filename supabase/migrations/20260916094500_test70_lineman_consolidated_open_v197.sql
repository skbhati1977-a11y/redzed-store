-- TEST70 V197: Cutting-Master parity — one consolidated Ready-to-Assign card per Lot.
begin;
create or replace function public.rr_real_chat_work_inbox_v83(p_status text default 'WORKING',p_search text default null,p_department_code text default null,p_limit integer default 500)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare v_base jsonb;v_cards jsonb;v_counts jsonb;v_role text;v_lineman_ids jsonb;r record;v_projection jsonb;v_lot text;
begin
 if auth.uid() is null then raise exception 'Login required.';end if;
 v_base:=public.rr_real_chat_work_inbox_v82(p_status,p_search,p_department_code,p_limit);v_cards:=coalesce(v_base->'cards','[]'::jsonb);v_role:=upper(coalesce(v_base#>>'{actor,role}','WORKER'));
 select coalesce(jsonb_agg(distinct p.auth_user_id),'[]'::jsonb) into v_lineman_ids from public.rr_user_profiles p where p.is_active and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE' and upper(coalesce(p.role_code,''))in('LINE_MANAGER','LINE_MAN') and public.rr_upm_core_department_v9077(p.department_code)='FABRICATION';
 if upper(coalesce(p_status,'WORKING'))='OPEN' and v_role in('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN') and(nullif(trim(p_department_code),'')is null or upper(trim(p_department_code))='FABRICATION')then
  for r in select distinct on(coalesce(x.card->>'canonical_lot_id',x.card->>'lot_no'))x.card from jsonb_array_elements(v_cards)x(card) where upper(coalesce(x.card->>'department_code',''))<>'FABRICATION' and exists(select 1 from jsonb_array_elements(coalesce(x.card->'actions','[]'::jsonb))a where upper(coalesce(a->>'code',''))='ASSIGN_WORKER') order by coalesce(x.card->>'canonical_lot_id',x.card->>'lot_no'),coalesce(x.card->>'event_at','')desc
  loop
   v_lot:=coalesce(r.card->>'lot_no',r.card->>'canonical_lot_id');
   v_projection:=r.card||jsonb_build_object('event_key','UPM_FABRICATION_ASSIGN:'||coalesce(r.card->>'canonical_lot_id',v_lot),'department_code','FABRICATION','department_name','Fabrication / Line Man','source_department_code',null,'visible_department_codes',jsonb_build_array('FABRICATION'),'worker_id',null,'worker_name','Shared Lineman Queue','visible_worker_ids',v_lineman_ids,'work_category','READY_TO_ASSIGN','message','Ready to Assign · Pending departments choose करें','group_only',false,'canonical_source','rr_upm_ready_to_assign_v9107','actions',jsonb_build_array(jsonb_build_object('code','ASSIGN_WORKER','label','ASSIGN WORK','href','real-universal-production-v770-v9059.html?mode=TEST&from=TEST70_REAL_CHAT&rrMode=ASSIGN&lot='||v_lot,'engine','rr_upm_ready_to_assign_v9107')));
   v_cards:=v_cards||jsonb_build_array(v_projection);
  end loop;
 end if;
 if upper(trim(coalesce(p_department_code,'')))='FABRICATION'then select coalesce(jsonb_agg(value),'[]'::jsonb)into v_cards from jsonb_array_elements(v_cards)where upper(coalesce(value->>'department_code',''))='FABRICATION';end if;
 select coalesce(jsonb_object_agg(department_code,cnt),'{}'::jsonb)into v_counts from(select coalesce(nullif(x->>'department_code',''),'UNKNOWN')department_code,count(*)cnt from jsonb_array_elements(v_cards)x group by 1)s;
 return jsonb_set(jsonb_set(jsonb_set(v_base,'{version}',to_jsonb('TEST70_REAL_CHAT_WORK_V83_LINEMAN_CONSOLIDATED_V197'::text),true),'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end $function$;
revoke all on function public.rr_real_chat_work_inbox_v83(text,text,text,integer)from public,anon;grant execute on function public.rr_real_chat_work_inbox_v83(text,text,text,integer)to authenticated;
commit;
