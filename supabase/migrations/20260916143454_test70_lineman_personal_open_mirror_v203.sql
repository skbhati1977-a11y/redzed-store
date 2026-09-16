-- TEST70 V203: hydrate the shared Lineman personal OPEN card from the same
-- consolidated Lot payload shown in the source department group and App.

begin;

create or replace function public.rr_real_chat_work_search_v14(
  p_status text default 'WORKING',
  p_search text default null,
  p_department_code text default null,
  p_limit integer default 500
) returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_base jsonb;
  v_cards jsonb:='[]'::jsonb;
  v_counts jsonb:='{}'::jsonb;
  v_status text:=upper(coalesce(p_status,'WORKING'));
  v_find text:=lower(trim(coalesce(p_search,'')));
  v_key text:=regexp_replace(lower(trim(coalesce(p_search,''))),'[^a-z0-9]','','g');
  v_fabrication_filter boolean:=public.rr_upm_core_department_v9077(p_department_code)='FABRICATION';
begin
  if auth.uid() is null then raise exception 'Login required.';end if;

  -- Hydration and search both need the complete card set. Fabrication-only
  -- filtering is therefore applied after the canonical source card is found.
  v_base:=public.rr_real_chat_work_search_v13(
    p_status,
    null,
    case when v_fabrication_filter then null else p_department_code end,
    p_limit
  );
  v_cards:=coalesce(v_base->'cards','[]'::jsonb);

  if v_status='OPEN' then
    select coalesce(jsonb_agg(
      case
        when public.rr_upm_core_department_v9077(x.card->>'department_code')='FABRICATION'
         and upper(coalesce(x.card->>'work_category',''))='READY_TO_ASSIGN'
         and peer.card is not null
        then x.card||jsonb_build_object(
          'canonical_source','rr_upm_department_colour_due_card_v9109',
          'qty',peer.card->'qty',
          'colour_count',peer.card->'colour_count',
          'colour_rows',peer.card->'colour_rows',
          'colour_codes',peer.card->'colour_codes',
          'colour_images',peer.card->'colour_images',
          'colour_name',peer.card->>'colour_name',
          'message','Ready to Assign · '||(peer.card->>'colour_count')||' colours · Pending departments choose करें',
          'mirrored_source_department_code',peer.card->>'department_code',
          'consolidated',true,
          'consolidated_scope','LOT'
        )
        else x.card
      end
      order by x.ord
    ),'[]'::jsonb)
      into v_cards
    from jsonb_array_elements(v_cards) with ordinality x(card,ord)
    left join lateral (
      select candidate as card
      from jsonb_array_elements(v_cards) candidate
      where coalesce(candidate->>'canonical_lot_id',candidate->>'lot_no')=
            coalesce(x.card->>'canonical_lot_id',x.card->>'lot_no')
        and public.rr_upm_core_department_v9077(candidate->>'department_code')<>'FABRICATION'
        and upper(coalesce(candidate->>'work_category',''))='READY_TO_ASSIGN'
        and candidate->>'consolidated_scope'='LOT_DEPARTMENT'
      order by coalesce(nullif(candidate->>'colour_count',''),'0')::integer desc,
               coalesce(nullif(candidate->>'qty',''),'0')::numeric desc
      limit 1
    ) peer on true;
  end if;

  if v_fabrication_filter then
    select coalesce(jsonb_agg(card order by ord),'[]'::jsonb)
      into v_cards
    from jsonb_array_elements(v_cards) with ordinality x(card,ord)
    where public.rr_upm_core_department_v9077(card->>'department_code')='FABRICATION';
  end if;

  if v_find<>'' then
    select coalesce(jsonb_agg(card order by ord),'[]'::jsonb)
      into v_cards
    from jsonb_array_elements(v_cards) with ordinality x(card,ord)
    where lower(card::text) like '%'||v_find||'%'
       or (v_key<>'' and regexp_replace(lower(card::text),'[^a-z0-9]','','g') like '%'||v_key||'%');
  end if;

  select coalesce(jsonb_object_agg(department_code,card_count),'{}'::jsonb)
    into v_counts
  from (
    select
      coalesce(nullif(card->>'department_code',''),'UNKNOWN') as department_code,
      count(*) as card_count
    from jsonb_array_elements(v_cards) x(card)
    group by 1
  ) counts;

  return jsonb_set(
    jsonb_set(
      jsonb_set(v_base,'{version}',to_jsonb('TEST70_LINEMAN_PERSONAL_OPEN_MIRROR_V203'::text),true),
      '{cards}',v_cards,true
    ),
    '{department_counts}',v_counts,true
  ) || jsonb_build_object('open_consolidation_scope','LOT_DEPARTMENT_AND_LINEMAN_PERSONAL');
end
$function$;

revoke all on function public.rr_real_chat_work_search_v14(text,text,text,integer) from public,anon;
grant execute on function public.rr_real_chat_work_search_v14(text,text,text,integer) to authenticated;

commit;
