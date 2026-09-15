begin;
create or replace function public.rr_real_chat_next_open_department_v1(p_lot_no text)
returns text language plpgsql stable security definer set search_path='' as $$
declare v_next text;
begin
 if auth.uid() is null then raise exception 'Login required.'; end if;
 if exists(select 1 from public.rr_upm_work_assignments_v8 a where upper(trim(a.lot_no))=upper(trim(p_lot_no)) and upper(coalesce(a.status,''))in('ASSIGNED','IN_PROGRESS')) then return null; end if;
 select d.code into v_next
 from (values
  (1,'PRINTING'),(2,'STICKER'),(3,'METAL_ID'),(4,'STITCHING'),(5,'OVERLOCK'),
  (6,'FOLDING'),(7,'KAAJ_BUTTON'),(8,'TEAK_TANKI'),(9,'THREAD_CUT'),
  (10,'QC'),(11,'PRESS'),(12,'PACKING'))d(seq,code)
 where exists(
  select 1 from jsonb_array_elements(coalesce(public.rr_upm_department_colour_due_card_v9109(d.code)->'lots','[]'::jsonb))x
  where upper(trim(x->>'lot_no'))=upper(trim(p_lot_no)) and jsonb_array_length(coalesce(x->'assign_rows','[]'::jsonb))>0)
 order by d.seq limit 1;
 return v_next;
end;$$;
revoke all on function public.rr_real_chat_next_open_department_v1(text)from public;
revoke all on function public.rr_real_chat_next_open_department_v1(text)from anon;
grant execute on function public.rr_real_chat_next_open_department_v1(text)to authenticated;

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
    or upper(coalesce(c->>'department_code',''))=public.rr_real_chat_next_open_department_v1(c->>'lot_no');
 select coalesce(jsonb_object_agg(department_code,cnt),'{}'::jsonb)into v_counts
 from(select coalesce(nullif(c->>'department_code',''),'UNKNOWN')department_code,count(*)cnt from jsonb_array_elements(v_cards)c group by 1)s;
 return jsonb_set(jsonb_set(jsonb_set(v_base,'{version}','"TEST70_REAL_CHAT_WORK_V79_SINGLE_CUSTODY"'::jsonb,true),'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end;$$;
revoke all on function public.rr_real_chat_work_inbox_v79(text,text,text,integer)from public;
revoke all on function public.rr_real_chat_work_inbox_v79(text,text,text,integer)from anon;
grant execute on function public.rr_real_chat_work_inbox_v79(text,text,text,integer)to authenticated;

create or replace function public.rr_real_chat_work_search_v5(p_status text default 'WORKING',p_search text default null,p_department_code text default null,p_limit integer default 500)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_base jsonb;v_find text:=lower(trim(coalesce(p_search,'')));v_key text:=regexp_replace(lower(trim(coalesce(p_search,''))),'[^a-z0-9]','','g');v_cards jsonb;v_counts jsonb;
begin
 if auth.uid() is null then raise exception 'Login required.'; end if;v_base:=public.rr_real_chat_work_inbox_v79(p_status,null,p_department_code,p_limit);if v_find=''then return v_base;end if;
 select coalesce(jsonb_agg(card order by ord),'[]'::jsonb)into v_cards from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb))with ordinality x(card,ord)where lower(card::text)like'%'||v_find||'%'or(v_key<>''and regexp_replace(lower(card::text),'[^a-z0-9]','','g')like'%'||v_key||'%');
 select coalesce(jsonb_object_agg(department_code,card_count),'{}'::jsonb)into v_counts from(select coalesce(nullif(card->>'department_code',''),'UNKNOWN')department_code,count(*)card_count from jsonb_array_elements(v_cards)x(card)group by 1)c;
 return jsonb_set(jsonb_set(v_base,'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end;$$;
revoke all on function public.rr_real_chat_work_search_v5(text,text,text,integer)from public;
revoke all on function public.rr_real_chat_work_search_v5(text,text,text,integer)from anon;
grant execute on function public.rr_real_chat_work_search_v5(text,text,text,integer)to authenticated;
commit;
