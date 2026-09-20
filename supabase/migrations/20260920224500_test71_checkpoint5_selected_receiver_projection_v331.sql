-- TEST71 Checkpoint 5 V331
-- Keep V330 as the canonical state core and add one authorization projection:
-- only the exact selected Line Man receives submit-handover actions.
begin;

alter function public.rr_real_chat_work_search_v317(text,text,text,integer)
rename to rr_real_chat_work_search_v317_core_v330;

create or replace function public.rr_real_chat_work_search_v317(
  p_status text default 'WORKING',p_search text default null,
  p_department_code text default null,p_limit integer default 500
) returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $function$
declare
  b jsonb;
  cards jsonb;
  counts jsonb;
  v_worker uuid:=public.rr_upm_current_worker_id_v9112();
begin
  b:=public.rr_real_chat_work_search_v317_core_v330(p_status,p_search,p_department_code,p_limit);
  select coalesce(jsonb_agg(
    case
      when c->>'source_module'='UPM_SUBMIT_HANDOFF'
       and upper(coalesce(c->>'source_status','')) in('WAITING_LM','ESCALATED','LM_ACCEPTED')
       and coalesce(c->>'worker_id','')<>coalesce(v_worker::text,'') then
        (c-'actions')||jsonb_build_object(
          'actions','[]'::jsonb,'requires_action',false,
          'action_waiting',case
            when upper(coalesce(c->>'source_status',''))='LM_ACCEPTED'
              then 'WAITING FOR '||upper(coalesce(c->>'receiver_name',c->>'worker_name','SELECTED LINE MAN'))||' COUNT'
            else 'WAITING FOR '||upper(coalesce(c->>'receiver_name',c->>'worker_name','SELECTED LINE MAN'))||' RECEIPT'
          end
        )
      else c
    end order by ord
  ),'[]'::jsonb) into cards
  from jsonb_array_elements(coalesce(b->'cards','[]'::jsonb)) with ordinality x(c,ord);

  select coalesce(jsonb_object_agg(d,n),'{}'::jsonb) into counts
  from(
    select coalesce(nullif(c->>'department_code',''),'UNKNOWN') d,count(*) n
    from jsonb_array_elements(cards)x(c) group by 1
  )s;

  return jsonb_set(
    jsonb_set(jsonb_set(b,'{version}',to_jsonb('V331_EXACT_FABRICATION_RECEIVER'::text),true),'{cards}',cards,true),
    '{department_counts}',counts,true
  );
end
$function$;

revoke all on function public.rr_real_chat_work_search_v317_core_v330(text,text,text,integer) from public,anon;
revoke all on function public.rr_real_chat_work_search_v317(text,text,text,integer) from public,anon;
grant execute on function public.rr_real_chat_work_search_v317(text,text,text,integer) to authenticated;

comment on function public.rr_real_chat_work_search_v317(text,text,text,integer) is
'TEST71 V331: V330 canonical state plus exact selected-receiver action authorization; non-receivers see a read-only waiting card.';

commit;
