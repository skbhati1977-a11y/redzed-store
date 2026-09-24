-- TEST71 universal role-scoped Cutting OPEN projection.
-- Keep OPEN and WORKING as projections of the canonical child/Lot state.
create or replace function public.rr_real_chat_work_search_v317(
  p_status text default 'WORKING',
  p_search text default null,
  p_department_code text default null,
  p_limit integer default 500
) returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  b jsonb;
  cards jsonb;
  counts jsonb;
  want text := upper(coalesce(p_status,'WORKING'));
  r record;
  p jsonb;
  actions jsonb;
begin
  b := public.rr_real_chat_work_search_v317_core_v401(p_status,p_search,p_department_code,p_limit);
  cards := coalesce(b->'cards','[]'::jsonb);

  if want = 'OPEN'
     and (nullif(trim(p_department_code),'') is null or upper(trim(p_department_code))='CUTTING') then
    for r in
      select mb.*, u.cb_code, u.cb_base_no
      from public.rr_real_chat_message_bridge_v70 mb
      left join public.rr_cb_units u on u.id::text=mb.source_record_id
      where mb.archived_at is null
        and mb.source_module='CUTTING'
        and mb.source_event_type='READY_FOR_CUTTING'
        and not exists (
          select 1 from public.rr_cutting_lots_v3 l
          where l.cb_unit_id::text=mb.source_record_id
        )
        and not exists (
          select 1 from public.rr_production_lots l
          where l.cb_unit_id::text=mb.source_record_id
        )
        and not exists (
          select 1 from public.rr_upm_lot_registry l
          where l.cb_unit_id::text=mb.source_record_id
        )
        and (coalesce(trim(p_search),'')='' or lower(mb.personal_payload::text) like '%'||lower(trim(p_search))||'%')
      order by mb.sent_at desc
      limit least(greatest(coalesce(p_limit,500),1),500)
    loop
      p := coalesce(r.personal_payload,r.group_payload,'{}'::jsonb);
      actions := coalesce(p->'next_actions','[]'::jsonb);
      if jsonb_array_length(actions)=0 then
        actions := jsonb_build_array(
          jsonb_build_object('code','CUTTING_SINGLE_LOT','label','SINGLE LOT','engine','EXISTING_CUTTING_RELEASE_CHAIN'),
          jsonb_build_object('code','CUTTING_MULTI_LOT','label','MULTI LOT','engine','EXISTING_CUTTING_RELEASE_CHAIN')
        );
      end if;
      if not exists (
        select 1 from jsonb_array_elements(cards) x
        where x->>'cb_unit_id'=r.source_record_id
          and upper(coalesce(x->>'department_code',''))='CUTTING'
      ) then
        cards := cards || jsonb_build_array(jsonb_build_object(
          'event_key','CUTTING_READY:'||r.id::text,
          'canonical_key',r.canonical_key,
          'canonical_lot_id',null,
          'lot_no',null,
          'cb_no',coalesce(p->>'cb_no',r.cb_base_no,r.cb_code),
          'cb_code',coalesce(p->>'cb_code',r.cb_code),
          'cb_unit_id',r.source_record_id,
          'chat_status','OPEN',
          'canonical_state','OPEN',
          'source_status','OPEN',
          'source_module','CUTTING',
          'source_event_type','READY_FOR_CUTTING',
          'work_category','READY_FOR_CUTTING',
          'department_code','CUTTING',
          'department_name','Cutting',
          'message',coalesce(p->>'message','Art / Print decision complete — Cutting Lot बनाना बाकी है'),
          'actions',actions,
          'requires_action',true,
          'action_code','CUTTING_SINGLE_LOT',
          'action_label','SINGLE LOT',
          'action_engine',coalesce(p->>'action_engine','EXISTING_CUTTING_RELEASE_CHAIN'),
          'event_at',r.sent_at
        ));
      end if;
    end loop;
  end if;

  select coalesce(jsonb_object_agg(d,n),'{}'::jsonb)
    into counts
  from (
    select coalesce(nullif(c->>'department_code',''),'UNKNOWN') d,count(*) n
    from jsonb_array_elements(cards) x(c)
    group by 1
  ) s;

  return jsonb_set(
    jsonb_set(
      jsonb_set(b,'{version}',to_jsonb('V402_OPEN_CUTTING_PROJECTION_V628'::text),true),
      '{cards}',cards,true
    ),
    '{department_counts}',counts,true
  );
end
$function$;

revoke all on function public.rr_real_chat_work_search_v317(text,text,text,integer) from public;
grant execute on function public.rr_real_chat_work_search_v317(text,text,text,integer) to authenticated;
grant execute on function public.rr_real_chat_work_search_v317(text,text,text,integer) to service_role;