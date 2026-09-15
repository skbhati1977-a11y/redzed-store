begin;

create or replace function public.rr_real_chat_work_inbox_v76(
  p_status text default 'WORKING', p_search text default null,
  p_department_code text default null, p_limit integer default 500
)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_base jsonb;
  v_cards jsonb;
  v_counts jsonb;
  v_state text:=upper(trim(coalesce(p_status,'WORKING')));
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  if v_state not in ('OPEN','WORKING','CLOSE') then raise exception 'Status must be OPEN, WORKING or CLOSE.'; end if;

  v_base:=public.rr_real_chat_work_inbox_v75(v_state,p_search,p_department_code,p_limit);

  -- Alter placement is decided only by the canonical journey's current stage.
  -- This removes inherited history cards such as source_status=COMPLETED from
  -- WORKING and prevents an active journey from appearing in CLOSE or OPEN.
  select coalesce(jsonb_agg(x.card order by x.ord),'[]'::jsonb)
  into v_cards
  from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb)) with ordinality x(card,ord)
  where coalesce(x.card->>'canonical_source','')<>'rr_upm_alter_journey_v740'
     or exists (
       select 1
       from public.rr_upm_alter_journey_v740 j
       where j.id=nullif(x.card->>'original_record_id','')::uuid
         and coalesce(j.open_qty,0)>0
         and ((v_state='WORKING' and upper(coalesce(j.stage,'')) not like 'CLOSED%')
           or (v_state='CLOSE' and upper(coalesce(j.stage,'')) like 'CLOSED%'))
     );

  select coalesce(jsonb_object_agg(department_code,cnt),'{}'::jsonb)
  into v_counts
  from (
    select coalesce(nullif(c->>'department_code',''),'UNKNOWN') department_code,count(*) cnt
    from jsonb_array_elements(v_cards) c
    group by 1
  ) s;

  return jsonb_set(
    jsonb_set(
      jsonb_set(v_base,'{version}','"TEST70_REAL_CHAT_WORK_V76_ALTER_SOURCE_TRUTH"'::jsonb,true),
      '{cards}',v_cards,true),
    '{department_counts}',v_counts,true);
end;
$$;
revoke all on function public.rr_real_chat_work_inbox_v76(text,text,text,integer) from public;
revoke all on function public.rr_real_chat_work_inbox_v76(text,text,text,integer) from anon;
grant execute on function public.rr_real_chat_work_inbox_v76(text,text,text,integer) to authenticated;

create or replace function public.rr_real_chat_work_search_v5(
  p_status text default 'WORKING',p_search text default null,
  p_department_code text default null,p_limit integer default 500
)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_base jsonb;
  v_find text:=lower(trim(coalesce(p_search,'')));
  v_key text:=regexp_replace(lower(trim(coalesce(p_search,''))),'[^a-z0-9]','','g');
  v_cards jsonb;
  v_counts jsonb;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  v_base:=public.rr_real_chat_work_inbox_v76(p_status,null,p_department_code,p_limit);
  if v_find='' then return v_base; end if;
  select coalesce(jsonb_agg(card order by ord),'[]'::jsonb) into v_cards
  from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb)) with ordinality x(card,ord)
  where lower(card::text) like '%'||v_find||'%'
     or (v_key<>'' and regexp_replace(lower(card::text),'[^a-z0-9]','','g') like '%'||v_key||'%');
  select coalesce(jsonb_object_agg(department_code,card_count),'{}'::jsonb) into v_counts
  from (
    select coalesce(nullif(card->>'department_code',''),'UNKNOWN') department_code,count(*) card_count
    from jsonb_array_elements(v_cards) x(card) group by 1
  ) c;
  return jsonb_set(jsonb_set(v_base,'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end;
$$;
revoke all on function public.rr_real_chat_work_search_v5(text,text,text,integer) from public;
revoke all on function public.rr_real_chat_work_search_v5(text,text,text,integer) from anon;
grant execute on function public.rr_real_chat_work_search_v5(text,text,text,integer) to authenticated;

commit;
