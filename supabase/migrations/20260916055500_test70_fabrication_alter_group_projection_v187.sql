-- TEST70 V187: include existing Lineman Alter/Remake forwarding in the
-- Fabrication virtual group without duplicating it in personal chats.
begin;

create or replace function public.rr_real_chat_work_inbox_v80(
  p_status text default 'WORKING',p_search text default null,p_department_code text default null,p_limit integer default 500
)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_base jsonb;v_cards jsonb;v_counts jsonb;v_role text;v_card jsonb;v_group jsonb;
begin
  if auth.uid() is null then raise exception 'Login required.';end if;
  v_base:=public.rr_real_chat_work_inbox_v79(p_status,p_search,p_department_code,p_limit);
  v_cards:=coalesce(v_base->'cards','[]'::jsonb);
  v_role:=upper(coalesce(v_base#>>'{actor,role}','WORKER'));
  if v_role in('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN')
     and(nullif(trim(p_department_code),'')is null or upper(trim(p_department_code))='FABRICATION') then
    for v_card in
      select value from jsonb_array_elements(v_cards)
      where value->>'canonical_source'='rr_upm_alter_journey_v740'
        and upper(coalesce(value->>'department_code',''))<>'FABRICATION'
    loop
      v_group:=v_card||jsonb_build_object(
        'event_key','UPM_FABRICATION_ALTER:'||coalesce(v_card->>'original_record_id',v_card->>'event_key'),
        'department_code','FABRICATION','department_name','Fabrication',
        'source_department_code',v_card->>'department_code',
        'current_department_code',coalesce(v_card->>'current_department_code',v_card->>'department_code'),
        'visible_department_codes',jsonb_build_array('FABRICATION'),
        'worker_id',null::uuid,'visible_worker_ids','[]'::jsonb,
        'group_only',true
      );
      v_cards:=v_cards||jsonb_build_array(v_group);
    end loop;
  end if;
  if upper(trim(coalesce(p_department_code,'')))='FABRICATION' then
    select coalesce(jsonb_agg(value),'[]'::jsonb) into v_cards
    from jsonb_array_elements(v_cards)
    where upper(coalesce(value->>'department_code',''))='FABRICATION';
  end if;
  select coalesce(jsonb_object_agg(department_code,cnt),'{}'::jsonb)into v_counts
  from(select coalesce(nullif(x->>'department_code',''),'UNKNOWN')department_code,count(*)cnt from jsonb_array_elements(v_cards)x group by 1)s;
  return jsonb_set(jsonb_set(jsonb_set(v_base,'{version}','"TEST70_REAL_CHAT_WORK_V80_FABRICATION_ALTER"'::jsonb,true),'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end;
$$;
revoke all on function public.rr_real_chat_work_inbox_v80(text,text,text,integer) from public,anon;
grant execute on function public.rr_real_chat_work_inbox_v80(text,text,text,integer) to authenticated;

create or replace function public.rr_real_chat_work_search_v7(
  p_status text default 'WORKING',p_search text default null,p_department_code text default null,p_limit integer default 500
)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_base jsonb;v_find text:=lower(trim(coalesce(p_search,'')));v_key text:=regexp_replace(lower(trim(coalesce(p_search,''))),'[^a-z0-9]','','g');v_cards jsonb;v_counts jsonb;
begin
  if auth.uid() is null then raise exception 'Login required.';end if;
  v_base:=public.rr_real_chat_work_inbox_v80(p_status,null,p_department_code,p_limit);
  if v_find='' then return v_base;end if;
  select coalesce(jsonb_agg(card order by ord),'[]'::jsonb)into v_cards
  from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb))with ordinality x(card,ord)
  where lower(card::text)like'%'||v_find||'%'or(v_key<>''and regexp_replace(lower(card::text),'[^a-z0-9]','','g')like'%'||v_key||'%');
  select coalesce(jsonb_object_agg(department_code,card_count),'{}'::jsonb)into v_counts
  from(select coalesce(nullif(card->>'department_code',''),'UNKNOWN')department_code,count(*)card_count from jsonb_array_elements(v_cards)x(card)group by 1)c;
  return jsonb_set(jsonb_set(v_base,'{cards}',v_cards,true),'{department_counts}',v_counts,true);
end;
$$;
revoke all on function public.rr_real_chat_work_search_v7(text,text,text,integer) from public,anon;
grant execute on function public.rr_real_chat_work_search_v7(text,text,text,integer) to authenticated;

commit;
