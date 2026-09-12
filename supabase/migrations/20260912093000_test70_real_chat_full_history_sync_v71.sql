-- TEST70 only: project the complete canonical UPM history into Real Chat.
-- Source workflow tables remain authoritative and are never mutated here.

create or replace function public.rr_real_chat_project_upm_v71(p_source text default null, p_record_id uuid default null)
returns integer
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_count integer := 0;
begin
  with events as (
    select 'ASSIGNMENT'::text source_kind, a.id record_id,
      'UPM_ASSIGNMENT:'||a.id canonical_key,
      case when upper(coalesce(a.status,''))='CANCELLED' then 'ASSIGNMENT_CANCELLED'
           when upper(coalesce(a.status,'')) in ('COMPLETED','CLOSED') then 'ASSIGNMENT_COMPLETED'
           else 'WORK_ASSIGNED' end source_event_type,
      a.department_code, a.assigned_by sender_user_id, a.worker_id receiver_worker_id,
      'ASSIGN_WORKER'::text action_code, 'ASSIGN WORKER'::text action_label,
      jsonb_build_object('lot_no',a.lot_no,'colour_code',a.colour_code,'colour_name',a.colour_name,
        'qty',a.assigned_qty,'assigned_qty',a.assigned_qty,'actual_rate',a.actual_rate,'status',a.status,
        'worker_name',a.worker_name_snapshot,'size_breakup',a.size_breakup,'remarks',a.remarks) personal_payload,
      jsonb_build_object('lot_no',a.lot_no,'colour_code',a.colour_code,'colour_name',a.colour_name,
        'qty',a.assigned_qty,'status',a.status,'worker_name',a.worker_name_snapshot) group_payload,
      coalesce(a.completed_at,a.cancelled_at,a.updated_at,a.assigned_at,a.created_at,now()) sent_at
    from public.rr_upm_work_assignments_v8 a
    where (p_source is null or p_source='ASSIGNMENT') and (p_record_id is null or a.id=p_record_id)

    union all
    select 'SUBMIT',s.id,'UPM_SUBMIT:'||s.id,'WORK_SUBMITTED',s.department_code,
      s.submitted_by,s.worker_id,'SUBMIT','SUBMIT',
      jsonb_build_object('lot_no',s.lot_no,'colour_code',s.colour_code,'colour_name',s.colour_name,
        'size_code',s.size_code,'qty',s.good_qty,'good_qty',s.good_qty,'status','SUBMITTED',
        'worker_name',s.worker_name,'remarks',s.remarks),
      jsonb_build_object('lot_no',s.lot_no,'colour_code',s.colour_code,'colour_name',s.colour_name,
        'size_code',s.size_code,'qty',s.good_qty,'status','SUBMITTED','worker_name',s.worker_name),
      coalesce(s.submitted_at,now())
    from public.rr_upm_dynamic_submit_history_v741 s
    where (p_source is null or p_source='SUBMIT') and (p_record_id is null or s.id=p_record_id)

    union all
    select 'ACTION',x.id,'UPM_ACTION:'||x.id,upper(coalesce(x.action_type,'WORK_ACTION')),
      coalesce(x.responsible_department_code,x.department_code),x.actor_user_id,
      coalesce(x.responsible_worker_id,x.worker_id),upper(coalesce(x.action_type,'WORK_ACTION')),
      replace(upper(coalesce(x.action_type,'WORK ACTION')),'_',' '),
      jsonb_build_object('lot_no',x.lot_no,'colour_code',x.colour_code,'colour_name',x.colour_name,
        'size_code',x.size_code,'qty',x.qty,'actual_rate',x.actual_rate,'status',upper(coalesce(x.action_type,'ACTION')),
        'worker_name',x.worker_name,'actor_name',x.actor_name,'remarks',x.remarks,
        'damage_reason_code',x.damage_reason_code,'claim_status',x.claim_status),
      jsonb_build_object('lot_no',x.lot_no,'colour_code',x.colour_code,'colour_name',x.colour_name,
        'size_code',x.size_code,'qty',x.qty,'status',upper(coalesce(x.action_type,'ACTION')),
        'worker_name',x.worker_name,'actor_name',x.actor_name),coalesce(x.created_at,now())
    from public.rr_upm_actions_v726 x
    where (p_source is null or p_source='ACTION') and (p_record_id is null or x.id=p_record_id)

    union all
    select 'ALTER_EVENT',e.id,'UPM_ALTER_EVENT:'||e.id,upper(coalesce(e.event_type,'ALTER_EVENT')),
      coalesce(j.responsible_department_code,j.origin_department_code),e.actor_id,
      coalesce(e.responsible_id,j.responsible_id,j.karigar_id),upper(coalesce(e.event_type,'ALTER_EVENT')),
      replace(upper(coalesce(e.event_type,'ALTER EVENT')),'_',' '),
      jsonb_build_object('lot_no',j.lot_no,'colour_code',j.colour_code,'colour_name',j.colour_name,
        'size_code',j.size_code,'qty',e.qty,'status',coalesce(e.to_stage,j.stage),
        'from_stage',e.from_stage,'to_stage',e.to_stage,'worker_name',coalesce(e.responsible_name,j.responsible_name,j.karigar_name),
        'actor_name',e.actor_name,'remarks',e.remarks),
      jsonb_build_object('lot_no',j.lot_no,'colour_code',j.colour_code,'colour_name',j.colour_name,
        'size_code',j.size_code,'qty',e.qty,'status',coalesce(e.to_stage,j.stage),
        'worker_name',coalesce(e.responsible_name,j.responsible_name,j.karigar_name),'actor_name',e.actor_name),
      coalesce(e.created_at,now())
    from public.rr_upm_alter_events_v740 e
    join public.rr_upm_alter_journey_v740 j on j.id=e.journey_id
    where (p_source is null or p_source='ALTER_EVENT') and (p_record_id is null or e.id=p_record_id)

    union all
    select 'RECTIFICATION',r.id,'UPM_RECTIFICATION:'||r.id,'RECTIFICATION_'||upper(coalesce(r.status,'OPEN')),
      coalesce(r.target_department_code,r.origin_department_code),r.created_by,
      coalesce(r.assigned_worker_id,r.original_worker_id),'RECTIFICATION',
      case when r.closed_at is null then 'RECTIFICATION' else 'RECTIFICATION CLOSED' end,
      jsonb_build_object('lot_no',r.lot_no,'colour_code',r.colour_code,'size_code',r.size_code,
        'qty',r.recalled_good_qty,'recalled_good_qty',r.recalled_good_qty,'resubmitted_good_qty',r.resubmitted_good_qty,
        'damage_qty',r.damage_qty,'alter_qty',r.alter_qty,'status',r.status,
        'worker_name',coalesce(r.assigned_worker_name,r.original_worker_name),'reason',r.reason,
        'remarks',r.remarks,'evidence_urls',r.evidence_urls),
      jsonb_build_object('lot_no',r.lot_no,'colour_code',r.colour_code,'size_code',r.size_code,
        'qty',r.recalled_good_qty,'status',r.status,'worker_name',coalesce(r.assigned_worker_name,r.original_worker_name),
        'reason',r.reason),coalesce(r.closed_at,r.resubmitted_at,r.assigned_at,r.created_at,now())
    from public.rr_upm_rectification_cases_v9101 r
    where (p_source is null or p_source='RECTIFICATION') and (p_record_id is null or r.id=p_record_id)
  ), resolved as (
    select e.*,d.linked_auth_user_id receiver_user_id,
      'test70-cb-purchase-real-chat-pilot.html?chat=personal&worker_id='||e.receiver_worker_id::text||
      '&message_key='||encode(convert_to(e.canonical_key,'UTF8'),'base64') deep_link
    from events e left join public.rr_worker_directory_unified_v1 d on d.worker_id=e.receiver_worker_id
  )
  insert into public.rr_real_chat_message_bridge_v70(
    canonical_key,source_module,source_record_id,source_event_type,department_code,
    sender_user_id,receiver_user_id,receiver_worker_id,action_code,action_label,
    personal_payload,group_payload,deep_link,sent_at)
  select canonical_key,'UPM',record_id::text,source_event_type,department_code,
    sender_user_id,receiver_user_id,receiver_worker_id,action_code,action_label,
    personal_payload,group_payload,deep_link,sent_at from resolved
  on conflict(canonical_key) do update set
    source_event_type=excluded.source_event_type,department_code=excluded.department_code,
    sender_user_id=excluded.sender_user_id,receiver_user_id=excluded.receiver_user_id,
    receiver_worker_id=excluded.receiver_worker_id,action_code=excluded.action_code,
    action_label=excluded.action_label,personal_payload=excluded.personal_payload,
    group_payload=excluded.group_payload,deep_link=excluded.deep_link,sent_at=excluded.sent_at;
  get diagnostics v_count=row_count;

  insert into public.rr_real_chat_receipts_v70(message_id,receiver_key,receiver_user_id,receiver_worker_id)
  select m.id,'WORKER:'||m.receiver_worker_id::text,m.receiver_user_id,m.receiver_worker_id
  from public.rr_real_chat_message_bridge_v70 m
  where m.source_module='UPM' and m.receiver_worker_id is not null
    and (p_record_id is null or m.source_record_id=p_record_id::text)
  on conflict(message_id,receiver_key) do update set receiver_user_id=excluded.receiver_user_id;

  insert into public.rr_real_chat_notification_links_v70(message_id,receiver_key,receiver_user_id,receiver_worker_id,deep_link)
  select m.id,'WORKER:'||m.receiver_worker_id::text,m.receiver_user_id,m.receiver_worker_id,m.deep_link
  from public.rr_real_chat_message_bridge_v70 m
  where m.source_module='UPM' and m.receiver_worker_id is not null
    and (p_record_id is null or m.source_record_id=p_record_id::text)
  on conflict(message_id,receiver_key) do update set receiver_user_id=excluded.receiver_user_id,deep_link=excluded.deep_link;
  return v_count;
end $$;

create or replace function public.rr_real_chat_sync_upm_history_v71()
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_uid uuid:=auth.uid(); v_count integer;
begin
  if v_uid is null or not public.rr_real_chat_is_global_staff_v70(v_uid) then
    raise exception 'STAFF_ACCESS_REQUIRED';
  end if;
  v_count:=public.rr_real_chat_project_upm_v71(null,null);
  return jsonb_build_object('ok',true,'events_reconciled',v_count);
end $$;
revoke all on function public.rr_real_chat_project_upm_v71(text,uuid) from public, anon, authenticated;
revoke all on function public.rr_real_chat_sync_upm_history_v71() from public, anon;
grant execute on function public.rr_real_chat_sync_upm_history_v71() to authenticated;

create or replace function public.rr_real_chat_upm_event_trigger_v71()
returns trigger language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_source text;
begin
  v_source:=case tg_table_name
    when 'rr_upm_work_assignments_v8' then 'ASSIGNMENT'
    when 'rr_upm_dynamic_submit_history_v741' then 'SUBMIT'
    when 'rr_upm_actions_v726' then 'ACTION'
    when 'rr_upm_alter_events_v740' then 'ALTER_EVENT'
    when 'rr_upm_rectification_cases_v9101' then 'RECTIFICATION' end;
  perform public.rr_real_chat_project_upm_v71(v_source,new.id);
  return new;
exception when others then
  raise warning 'TEST70 Real Chat projection deferred for %.%: %',tg_table_name,new.id,sqlerrm;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['rr_upm_work_assignments_v8','rr_upm_dynamic_submit_history_v741',
    'rr_upm_actions_v726','rr_upm_alter_events_v740','rr_upm_rectification_cases_v9101']
  loop
    execute format('drop trigger if exists rr_real_chat_auto_sync_v71 on public.%I',t);
    execute format('create trigger rr_real_chat_auto_sync_v71 after insert or update on public.%I for each row execute function public.rr_real_chat_upm_event_trigger_v71()',t);
  end loop;
end $$;

-- Initial, repeat-safe historical reconciliation.
select public.rr_real_chat_project_upm_v71(null,null);

do $$ begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='rr_real_chat_message_bridge_v70') then
    alter publication supabase_realtime add table public.rr_real_chat_message_bridge_v70;
  end if;
end $$;

comment on function public.rr_real_chat_sync_upm_history_v71() is
  'TEST70 idempotent reconciliation of canonical assignment, submit, action, alter/remake and rectification history into Real Chat.';
