-- TEST71 V320
-- Keep one canonical Real Chat search read, but resolve receipt-backed
-- assignments from every assignment key shape emitted by the existing V14
-- projection. This repairs Group Chat mirroring without creating another
-- lifecycle engine.
create or replace function public.rr_real_chat_work_search_v317(
  p_status text default 'WORKING',
  p_search text default null,
  p_department_code text default null,
  p_limit integer default 500
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  b jsonb;
  cards jsonb;
  counts jsonb;
  want text:=upper(coalesce(p_status,'WORKING'));
begin
  -- One base read only. The retired V315 double-search must not return.
  b:=public.rr_real_chat_work_search_v14(want,p_search,p_department_code,p_limit);
  cards:=coalesce(b->'cards','[]'::jsonb);

  with raw_keys as (
    select
      ord,
      c,
      coalesce(
        nullif(c->>'assignment_id',''),
        case
          when coalesce(c->>'event_key','') like 'UPM_ASSIGNMENT:%'
            then nullif(regexp_replace(c->>'event_key','^UPM_ASSIGNMENT:',''),'')
        end,
        case
          when coalesce(c->>'canonical_key','') like 'UPM_ASSIGNMENT:%'
            then nullif(regexp_replace(c->>'canonical_key','^UPM_ASSIGNMENT:',''),'')
        end,
        nullif(c->>'original_record_id','')
      ) assignment_key
    from jsonb_array_elements(cards) with ordinality z(c,ord)
  ), raw_cards as (
    select
      ord,
      c,
      case
        when assignment_key ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
          then assignment_key::uuid
      end assignment_id
    from raw_keys
  ), x as (
    select
      raw.ord,
      raw.c,
      a.id aid,
      a.status ast,
      r.status rst,
      r.confirmed_at,
      e.id eid,
      e.status est,
      case
        when r.assignment_id is null then null
        when upper(r.status)='PENDING' then 'ACCEPT_PENDING'
        when upper(r.status)='CONFIRMED' and upper(a.status)='IN_PROGRESS' then 'WORKING'
        when upper(a.status)='COMPLETED' then 'CLOSE'
        else upper(a.status)
      end resolved
    from raw_cards raw
    left join public.rr_upm_work_assignments_v8 a
      on a.id=raw.assignment_id
    left join public.rr_upm_assignment_receipts_v9112 r
      on r.assignment_id=a.id
    left join lateral (
      select q.id,q.status
      from public.rr_upm_responsibility_events_v800 q
      where q.assignment_id=a.id::text
        and q.event_type='ASSIGN_HANDOVER'
      order by q.created_at desc
      limit 1
    ) e on true
  )
  select coalesce(jsonb_agg(
    case
      when aid is null or rst is null then c
      else (c-'actions')||jsonb_build_object(
        'assignment_id',aid,
        'assignment_status',ast,
        'receipt_status',rst,
        'resolved_work_state',resolved,
        'responsibility_event_id',eid,
        'source_status',case
          when resolved='ACCEPT_PENDING' then 'ASSIGNED'
          when resolved='WORKING' then 'WORKING'
          when resolved='CLOSE' then 'CLOSE'
          else c->>'source_status'
        end,
        'message',case
          when resolved='ACCEPT_PENDING'
            then coalesce(c->>'worker_name','Worker')||' को काम दिया · Accept बाकी'
          when resolved='WORKING'
            then coalesce(c->>'worker_name','Worker')||' · काम जारी है'
          else c->>'message'
        end,
        'actions',case
          when resolved='ACCEPT_PENDING' and eid is not null then
            jsonb_build_array(jsonb_build_object(
              'code','CONFIRM_RECEIVED_PCS',
              'label','ACCEPT & COUNT',
              'assignment_id',aid,
              'event_id',eid,
              'engine','rr_upm_accept_physical_count_batch_v802'
            ))
          else coalesce(c->'actions','[]'::jsonb)
        end
      )
    end
    order by ord
  ),'[]'::jsonb)
  into cards
  from x;

  select coalesce(jsonb_object_agg(d,n),'{}'::jsonb)
  into counts
  from (
    select coalesce(nullif(c->>'department_code',''),'UNKNOWN') d,count(*) n
    from jsonb_array_elements(cards) x(c)
    group by 1
  ) s;

  return jsonb_set(
    jsonb_set(
      jsonb_set(b,'{version}',to_jsonb('V320_EXACT_ASSIGNMENT_KEY_LIFECYCLE'::text),true),
      '{cards}',cards,true
    ),
    '{department_counts}',counts,true
  );
end
$$;

comment on function public.rr_real_chat_work_search_v317(text,text,text,integer)
is 'TEST71 V320: one-read V317 lifecycle mirror with exact assignment_id, event_key, canonical_key, and original_record_id resolution.';
