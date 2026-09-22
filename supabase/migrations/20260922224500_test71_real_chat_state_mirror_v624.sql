-- TEST71 V624: one read-time lifecycle state across the Real Chat envelope,
-- Department Group payload and Personal Chat payload. Historical business and
-- audit rows remain immutable; the bounded canonical history projection is
-- normalized after authority filtering and before the existing privacy redactor.
begin;

create or replace function public.rr_real_chat_state_payload_v624(
  p_payload jsonb,
  p_state text
) returns jsonb
language sql
immutable
set search_path=''
as $function$
with state as (
  select case
    when upper(coalesce(p_state,'')) in('OPEN','WORKING','CLOSE','REOPENED')
      then upper(p_state)
    else 'WORKING'
  end value
)
select case
  when state.value='CLOSE' then
    (coalesce(p_payload,'{}'::jsonb)-'action_href'-'action_engine'-'next_actions')
      ||jsonb_build_object('canonical_state','CLOSE','next_actions','[]'::jsonb)
  else
    coalesce(p_payload,'{}'::jsonb)
      ||jsonb_build_object('canonical_state',state.value)
end
from state
$function$;

revoke all on function public.rr_real_chat_state_payload_v624(jsonb,text)
  from public,anon,authenticated;
grant execute on function public.rr_real_chat_state_payload_v624(jsonb,text)
  to service_role;

create or replace function public.rr_real_chat_conversation_history_v83(
  p_limit integer default 2000
) returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $function$
declare
  v_core jsonb;
  v_synced jsonb;
begin
  -- The core applies row authority first. State mirroring cannot reveal any
  -- protected personal payload because unauthorized payloads are already {}.
  v_core:=public.rr_real_chat_conversation_history_v83_core_v401(p_limit);

  select coalesce(jsonb_agg(
    row_value||jsonb_build_object(
      'personal_payload',public.rr_real_chat_state_payload_v624(
        row_value->'personal_payload',row_value->>'canonical_state'
      ),
      'group_payload',public.rr_real_chat_state_payload_v624(
        row_value->'group_payload',row_value->>'canonical_state'
      )
    ) order by ordinal
  ),'[]'::jsonb)
  into v_synced
  from jsonb_array_elements(coalesce(v_core,'[]'::jsonb))
    with ordinality as rows(row_value,ordinal);

  -- Existing V401/V612 backend redaction remains the final payload boundary.
  return public.rr_real_chat_redact_v401(v_synced);
end
$function$;

revoke all on function public.rr_real_chat_conversation_history_v83(integer)
  from public,anon;
grant execute on function public.rr_real_chat_conversation_history_v83(integer)
  to authenticated,service_role;

comment on function public.rr_real_chat_conversation_history_v83(integer) is
  'TEST71 V624 canonical history: envelope, Group and Personal payload lifecycle states agree; CLOSE carries no stale action; V401 privacy redaction remains final.';

create or replace function public.rr_test_real_chat_state_mirror_v624()
returns jsonb
language plpgsql
security definer
set search_path='public'
set statement_timeout='30s'
as $function$
declare
  v_profile public.rr_user_profiles%rowtype;
  v_history jsonb;
  v_existing jsonb;
  v_future_close jsonb;
  v_future_working jsonb;
begin
  select * into v_profile
  from public.rr_user_profiles
  where auth_user_id=auth.uid()
    and is_active
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE';

  if v_profile.id is null
    or v_profile.full_name<>'TEST71 E2E Super Admin'
    or upper(coalesce(v_profile.role_code,''))<>'SUPER_ADMIN' then
    raise exception 'Dedicated TEST71 E2E Super Admin required.' using errcode='42501';
  end if;
  if coalesce((public.rr_upm_effective_identity_v200()->>'on_behalf')::boolean,false) then
    raise exception 'Return Act As to signed-in TEST71 E2E Super Admin first.' using errcode='42501';
  end if;

  v_history:=public.rr_real_chat_conversation_history_v83(5000);
  select value into v_existing
  from jsonb_array_elements(v_history)
  where value->>'source_event_type'='CUTTING_RELEASE_SUCCEEDED'
    and upper(coalesce(value#>>'{personal_payload,lot_no}',value#>>'{group_payload,lot_no}',''))='E2E-FRESH-03'
  order by value->>'sent_at' desc
  limit 1;

  v_future_close:=public.rr_real_chat_state_payload_v624(
    jsonb_build_object(
      'lot_no','TEST71-FUTURE-CLOSE',
      'action_href','must-be-removed',
      'action_engine','must-be-removed',
      'next_actions',jsonb_build_array(jsonb_build_object('code','SUBMIT'))
    ),
    'CLOSE'
  );
  v_future_working:=public.rr_real_chat_state_payload_v624(
    jsonb_build_object(
      'lot_no','TEST71-FUTURE-WORKING',
      'next_actions',jsonb_build_array(jsonb_build_object('code','SUBMIT'))
    ),
    'WORKING'
  );

  return jsonb_build_object(
    'ok',v_existing is not null
      and v_existing->>'canonical_state'='CLOSE'
      and v_existing#>>'{personal_payload,canonical_state}'='CLOSE'
      and v_existing#>>'{group_payload,canonical_state}'='CLOSE'
      and v_existing#>'{personal_payload,next_actions}'='[]'::jsonb
      and v_existing#>'{group_payload,next_actions}'='[]'::jsonb
      and v_future_close->>'canonical_state'='CLOSE'
      and v_future_close->'next_actions'='[]'::jsonb
      and not(v_future_close?'action_href')
      and not(v_future_close?'action_engine')
      and v_future_working->>'canonical_state'='WORKING'
      and jsonb_array_length(v_future_working->'next_actions')=1,
    'original_case',jsonb_build_object(
      'canonical_key',v_existing->>'canonical_key',
      'envelope_state',v_existing->>'canonical_state',
      'personal_state',v_existing#>>'{personal_payload,canonical_state}',
      'group_state',v_existing#>>'{group_payload,canonical_state}',
      'personal_next_actions',v_existing#>'{personal_payload,next_actions}',
      'group_next_actions',v_existing#>'{group_payload,next_actions}'
    ),
    'future_close',v_future_close,
    'future_working',v_future_working
  );
end
$function$;

revoke all on function public.rr_test_real_chat_state_mirror_v624()
  from public,anon,authenticated,service_role;
grant execute on function public.rr_test_real_chat_state_mirror_v624()
  to authenticated;

comment on function public.rr_test_real_chat_state_mirror_v624() is
  'TEST71 V624 exact original E2E-FRESH-03 projection plus synthetic future CLOSE/WORKING rule proof; no business row mutation.';

notify pgrst,'reload schema';
commit;
