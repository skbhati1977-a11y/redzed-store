create or replace function public.rr_real_chat_work_search_v1(
  p_status text default 'WORKING',
  p_search text default null,
  p_department_code text default null,
  p_limit integer default 500
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_base jsonb;
  v_find text:=lower(trim(coalesce(p_search,'')));
  v_find_key text:=regexp_replace(lower(trim(coalesce(p_search,''))),'[^a-z0-9]','','g');
  v_cards jsonb; v_counts jsonb;
  v_related_lots text[]:=array[]::text[];
  v_related_terms text[]:=array[]::text[];
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  v_base:=public.rr_real_chat_work_inbox_v71(
    p_status=>p_status,p_search=>null,p_department_code=>p_department_code,
    p_limit=>least(greatest(coalesce(p_limit,500),1),500));
  if v_find='' then return v_base; end if;

  with relations as (
    select m value from jsonb_array_elements(public.rr_real_chat_media_map_v1()) m
    union all
    select jsonb_build_object(
      'lot_no',l.lot_no,'cb_no',u.cb_code,'cb_base_no',u.cb_base_no,
      'cb_unit_id',l.cb_unit_id,'legacy_state',l.state
    )
    from public.rr_cutting_legacy_lot_link_v1 l
    join public.rr_cb_units u on u.id=l.cb_unit_id
    where l.active
  ), matched as (
    select value
    from relations
    where lower(value::text) like '%'||v_find||'%'
       or (v_find_key<>'' and regexp_replace(lower(value::text),'[^a-z0-9]','','g') like '%'||v_find_key||'%')
  )
  select
    coalesce(array_agg(distinct upper(trim(value->>'lot_no')))
      filter(where nullif(trim(value->>'lot_no'),'') is not null),array[]::text[]),
    coalesce(array_agg(distinct lower(term)) filter(where nullif(trim(term),'') is not null),array[]::text[])
  into v_related_lots,v_related_terms
  from matched
  cross join lateral unnest(array[
    value->>'lot_no',value->>'cb_no',value->>'cb_base_no',value->>'art_no'
  ]) term;

  v_related_terms:=array_append(v_related_terms,v_find);

  select coalesce(jsonb_agg(card order by ord),'[]'::jsonb) into v_cards
  from jsonb_array_elements(coalesce(v_base->'cards','[]'::jsonb)) with ordinality x(card,ord)
  where lower(card::text) like '%'||v_find||'%'
     or (v_find_key<>'' and regexp_replace(lower(card::text),'[^a-z0-9]','','g') like '%'||v_find_key||'%')
     or upper(trim(coalesce(card->>'lot_no','')))=any(v_related_lots);

  select coalesce(jsonb_object_agg(department_code,card_count),'{}'::jsonb) into v_counts
  from (
    select coalesce(nullif(card->>'department_code',''),'UNKNOWN') department_code,count(*) card_count
    from jsonb_array_elements(v_cards) x(card) group by 1
  ) c;

  return jsonb_set(
    jsonb_set(jsonb_set(v_base,'{cards}',v_cards,true),'{department_counts}',v_counts,true),
    '{related_terms}',to_jsonb(v_related_terms),true);
end;
$function$;

revoke all on function public.rr_real_chat_work_search_v1(text,text,text,integer) from public, anon;
grant execute on function public.rr_real_chat_work_search_v1(text,text,text,integer) to authenticated, service_role;
