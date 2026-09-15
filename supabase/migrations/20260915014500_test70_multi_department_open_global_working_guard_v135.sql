begin;
create or replace function public.rr_real_chat_work_inbox_v79(p_status text default 'WORKING',p_search text default null,p_department_code text default null,p_limit integer default 500)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_base jsonb;v_cards jsonb;v_counts jsonb;
begin
 if auth.uid() is null then raise exception 'Login required.'; end if;
 v_base:=public.rr_real_chat_work_inbox_v78(p_status,p_search,p_department_code,p_limit);
 if upper(coalesce(p_status,'WORKING'))<>'OPEN' then return v_base; end if;
 select coalesce(jsonb_agg(c order by ord),'[]'::jsonb)into v_cards
 from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb))with ordinality x(c,ord)
 where c->>'work_category'<>'READY_TO_ASSIGN'
    or not exists(
      select 1 from public.rr_upm_work_assignments_v8 a
      where upper(trim(a.lot_no))=upper(trim(c->>'lot_no'))
        and upper(coalesce(a.status,''))in('ASSIGNED','IN_PROGRESS'));
 select coalesce(jsonb_object_agg(department_code,cnt),'{}'::jsonb)into v_counts
 from(select coalesce(nullif(c->>'department_code',''),'UNKNOWN')department_code,count(*)cnt from jsonb_array_elements(v_cards)c group by 1)s;
 return jsonb_set(jsonb_set(jsonb_set(v_base,'{version}','"TEST70_REAL_CHAT_WORK_V79_MULTI_OPEN_WORKING_GUARD"'::jsonb,true),'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end;$$;
revoke all on function public.rr_real_chat_work_inbox_v79(text,text,text,integer)from public;
revoke all on function public.rr_real_chat_work_inbox_v79(text,text,text,integer)from anon;
grant execute on function public.rr_real_chat_work_inbox_v79(text,text,text,integer)to authenticated;
drop function if exists public.rr_real_chat_next_open_department_v1(text);
commit;
