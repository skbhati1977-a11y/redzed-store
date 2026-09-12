-- TEST70 only: globally distinguish an immutable performed-action message from
-- the current pending workflow task. Source workflow tables stay authoritative.
begin;

create or replace function public.rr_real_chat_lifecycle_v77()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_message text;
begin
  v_message:=case upper(coalesce(new.source_event_type,''))
    when 'ALTER_FILL' then 'Alter दर्ज किया'
    when 'LM_ACCEPT_REQUEST' then 'Line Man को भेजा'
    when 'LM_ACCEPT' then 'Line Man ने स्वीकार किया'
    when 'REMAKE_ISSUE' then 'Remake के लिए Cutting Master को भेजा'
    when 'RECEIVE_FROM_MASTER' then 'Cutting Master से वापस मिला'
    when 'DELIVER_TO_KARIGAR' then 'कारीगर को Remake दिया'
    when 'KARIGAR_SUBMIT_GOOD' then 'कारीगर ने Remake जमा किया'
    when 'RECEIVE_FROM_KARIGAR' then 'कारीगर से Remake प्राप्त किया'
    when 'WORK_SUBMITTED' then 'काम जमा किया'
    when 'ASSIGNMENT_COMPLETED' then 'दिया गया काम पूरा हुआ'
    when 'ASSIGNMENT_CANCELLED' then 'दिया गया काम रद्द हुआ'
    when 'DEPARTMENT_RATE_UPDATED' then 'Department rate भरा'
    when 'ASSIGNMENT_RATE_UPDATED' then 'Working rate भरा'
    when 'LOT_OPEN' then case when new.canonical_key like 'LOT_RELEASE:%' then 'CB से Lot बनाया' end
    else null end;

  if v_message is not null then
    new.personal_payload:=new.personal_payload||jsonb_build_object('message',v_message);
    new.group_payload:=new.group_payload||jsonb_build_object('message',v_message);
  end if;

  -- Every alter/remake event row records an action that has already happened.
  -- The current actionable state continues to come only from the canonical
  -- inbox/action registry, so old action cards cannot remain falsely pending.
  if new.canonical_key like 'UPM_ALTER_EVENT:%'
     or (new.canonical_key like 'LOT_RELEASE:%' and new.personal_payload->>'message'='CB से Lot बनाया') then
    new.personal_payload:=new.personal_payload||jsonb_build_object('message_status','COMPLETED');
    new.group_payload:=new.group_payload||jsonb_build_object('message_status','COMPLETED');
    new.action_code:=null;
    new.action_label:=null;
  end if;
  return new;
end $$;
revoke all on function public.rr_real_chat_lifecycle_v77() from public,anon,authenticated;

drop trigger if exists rr_real_chat_lifecycle_v77 on public.rr_real_chat_message_bridge_v70;
create trigger rr_real_chat_lifecycle_v77
before insert or update on public.rr_real_chat_message_bridge_v70
for each row execute function public.rr_real_chat_lifecycle_v77();

-- Legacy + present: pass every existing bridge row through the exact same
-- lifecycle, truthful-actor and two-way participant trigger chain.
update public.rr_real_chat_message_bridge_v70 set source_event_type=source_event_type;

-- A permanent, read-only staff assertion for all canonical projectors.
create or replace function public.rr_real_chat_mapping_audit_v77()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_uid uuid:=auth.uid(); v_result jsonb;
begin
  if v_uid is null or not public.rr_real_chat_is_global_staff_v70(v_uid) then
    raise exception 'STAFF_ACCESS_REQUIRED';
  end if;
  with expected as (
    select 'E2E'::text source,count(distinct canonical_key)::bigint expected,
      count(distinct b.canonical_key)::bigint mapped
    from public.rr_real_chat_e2e_event_source_v71 e
    left join public.rr_real_chat_message_bridge_v70 b using(canonical_key)
    union all
    select 'UPM_ASSIGNMENT',count(*),count(b.id) from public.rr_upm_work_assignments_v8 x
      left join public.rr_real_chat_message_bridge_v70 b on b.canonical_key='UPM_ASSIGNMENT:'||x.id::text
    union all
    select 'UPM_SUBMIT',count(*),count(b.id) from public.rr_upm_dynamic_submit_history_v741 x
      left join public.rr_real_chat_message_bridge_v70 b on b.canonical_key='UPM_SUBMIT:'||x.id::text
    union all
    select 'UPM_ACTION',count(*),count(b.id) from public.rr_upm_actions_v726 x
      left join public.rr_real_chat_message_bridge_v70 b on b.canonical_key='UPM_ACTION:'||x.id::text
    union all
    select 'UPM_ALTER_EVENT',count(*),count(b.id) from public.rr_upm_alter_events_v740 x
      left join public.rr_real_chat_message_bridge_v70 b on b.canonical_key='UPM_ALTER_EVENT:'||x.id::text
    union all
    select 'UPM_RECTIFICATION',count(*),count(b.id) from public.rr_upm_rectification_cases_v9101 x
      left join public.rr_real_chat_message_bridge_v70 b on b.canonical_key='UPM_RECTIFICATION:'||x.id::text
    union all
    select 'CUTTING_LOT',count(*),count(*) filter(where exists(
      select 1 from public.rr_real_chat_message_bridge_v70 b where b.source_module='CUTTING'
      and b.canonical_key like 'LOT_RELEASE:%' and b.personal_payload->>'lot_no'=x.lot_no))
      from public.rr_cutting_lots_v3 x
  )
  select jsonb_build_object(
    'ok',bool_and(expected=mapped),
    'expected',sum(expected),'mapped',sum(mapped),'missing',sum(expected-mapped),
    'sources',jsonb_agg(jsonb_build_object('source',source,'expected',expected,
      'mapped',mapped,'missing',expected-mapped) order by source))
  into v_result from expected;
  return v_result;
end $$;
revoke all on function public.rr_real_chat_mapping_audit_v77() from public,anon;
grant execute on function public.rr_real_chat_mapping_audit_v77() to authenticated;

comment on function public.rr_real_chat_lifecycle_v77() is
'TEST70 global legacy/present/future performed-action lifecycle reconciliation; canonical inbox remains the sole pending-action source.';
comment on function public.rr_real_chat_mapping_audit_v77() is
'TEST70 row-level source-to-message assertions across E2E, UPM and Cutting canonical sources.';
commit;
