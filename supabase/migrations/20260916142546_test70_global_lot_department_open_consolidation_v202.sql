-- TEST70 V202: one canonical OPEN card per Lot + Department everywhere.
-- App keeps its colour rows; Real Chat group/personal projections receive the
-- same rows as one consolidated card with one guarded ASSIGN WORKER action.

begin;

create or replace function public.rr_real_chat_work_search_v13(
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
begin
  if auth.uid() is null then raise exception 'Login required.';end if;

  -- Search only after consolidation. Searching C1 must still return the full
  -- Lot card (all colours), never recreate a one-colour split card.
  v_base:=public.rr_real_chat_work_search_v12(
    p_status,
    null,
    p_department_code,
    p_limit
  );
  v_cards:=coalesce(v_base->'cards','[]'::jsonb);

  if v_status='OPEN' then
    with expanded as (
      select
        x.card,
        x.ord::bigint as ord,
        coalesce(
          nullif(x.card->>'canonical_lot_id',''),
          nullif(x.card->>'lot_no','')
        ) as lot_key,
        public.rr_upm_core_department_v9077(x.card->>'department_code') as department_key,
        case
          when upper(coalesce(x.card->>'work_category',''))='READY_TO_ASSIGN'
           and coalesce(nullif(x.card->>'canonical_lot_id',''),nullif(x.card->>'lot_no','')) is not null
           and nullif(x.card->>'department_code','') is not null
          then true else false
        end as is_ready
      from jsonb_array_elements(v_cards) with ordinality x(card,ord)
    ),
    ready_unique as (
      select distinct on(lot_key,department_key,colour_key)
        card,ord,lot_key,department_key,colour_key
      from (
        select
          e.*,
          coalesce(
            nullif(upper(e.card->>'colour_code'),''),
            nullif(e.card->>'original_record_id',''),
            nullif(e.card->>'event_key',''),
            e.ord::text
          ) as colour_key
        from expanded e
        where e.is_ready
      ) d
      order by lot_key,department_key,colour_key,
        coalesce(card->>'event_at','') desc,ord desc
    ),
    representatives as (
      select distinct on(lot_key,department_key)
        lot_key,department_key,card
      from ready_unique
      order by lot_key,department_key,coalesce(card->>'event_at','') desc,ord desc
    ),
    grouped as (
      select
        lot_key,
        department_key,
        min(ord) as first_ord,
        sum(coalesce(nullif(card->>'qty',''),'0')::numeric) as total_qty,
        count(*)::integer as colour_count,
        jsonb_agg(
          jsonb_build_object(
            'colour_code',coalesce(nullif(card->>'colour_code',''),colour_key),
            'colour_name',coalesce(nullif(card->>'colour_name',''),nullif(card->>'colour_code',''),colour_key),
            'qty',coalesce(nullif(card->>'qty',''),'0')::numeric,
            'size_breakup',coalesce(card->'size_breakup','[]'::jsonb),
            'thumbnail_url',coalesce(card#>>'{colour_images,0}',card#>>'{art_images,0}')
          )
          order by coalesce(nullif(card->>'colour_code',''),colour_key)
        ) as colour_rows,
        jsonb_agg(to_jsonb(coalesce(nullif(card->>'colour_code',''),colour_key))
          order by coalesce(nullif(card->>'colour_code',''),colour_key)) as colour_codes
      from ready_unique
      group by lot_key,department_key
    ),
    images as (
      select
        r.lot_key,
        r.department_key,
        coalesce(
          jsonb_agg(distinct image.value) filter(where image.value is not null),
          '[]'::jsonb
        ) as colour_images
      from ready_unique r
      left join lateral jsonb_array_elements(
        case
          when jsonb_typeof(r.card->'colour_images')='array' and jsonb_array_length(r.card->'colour_images')>0
            then r.card->'colour_images'
          when jsonb_typeof(r.card->'art_images')='array'
            then r.card->'art_images'
          else '[]'::jsonb
        end
      ) image on true
      group by r.lot_key,r.department_key
    ),
    output as (
      select e.ord,e.card
      from expanded e
      where not e.is_ready

      union all

      select
        g.first_ord as ord,
        (
          r.card
          - 'event_key'
          - 'colour_code'
          - 'colour_name'
          - 'size_code'
          - 'qty'
          - 'colour_rows'
          - 'colour_codes'
          - 'colour_count'
          - 'colour_images'
        ) || jsonb_build_object(
          'event_key','UPM_OPEN_LOT:'||g.lot_key||':'||g.department_key,
          'canonical_source','rr_upm_department_colour_due_card_v9109',
          'department_code',g.department_key,
          'visible_department_codes',jsonb_build_array(g.department_key),
          'qty',g.total_qty,
          'colour_count',g.colour_count,
          'colour_rows',g.colour_rows,
          'colour_codes',g.colour_codes,
          'colour_images',coalesce(i.colour_images,'[]'::jsonb),
          'colour_name',g.colour_count||' colours',
          'message','Ready to Assign · '||g.colour_count||' colours',
          'consolidated',true,
          'consolidated_scope','LOT_DEPARTMENT'
        ) as card
      from grouped g
      join representatives r using(lot_key,department_key)
      left join images i using(lot_key,department_key)
    )
    select coalesce(jsonb_agg(card order by ord),'[]'::jsonb)
      into v_cards
    from output;
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
      jsonb_set(v_base,'{version}',to_jsonb('TEST70_GLOBAL_LOT_DEPARTMENT_OPEN_V202'::text),true),
      '{cards}',v_cards,true
    ),
    '{department_counts}',v_counts,true
  ) || jsonb_build_object('open_consolidation_scope','LOT_DEPARTMENT');
end
$function$;

revoke all on function public.rr_real_chat_work_search_v13(text,text,text,integer) from public,anon;
grant execute on function public.rr_real_chat_work_search_v13(text,text,text,integer) to authenticated;

commit;
