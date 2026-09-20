-- TEST71 Checkpoint 5
-- Repair the existing Purchase/Fabrication/short-recovery projections only.
-- Authoritative Purchase, UPM assignment, V204 submit and responsibility tables
-- remain the single workflow engines.
begin;

-- Conversation history must authorize against the effective Act As identity,
-- not the signed-in Super Admin profile after delegation is active.
create or replace function public.rr_real_chat_conversation_history_v83(
  p_limit integer default 2000
) returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_profile public.rr_user_profiles%rowtype;
  v_identity jsonb;
  v_worker uuid;
  v_role text;
  v_global boolean;
  v_costing boolean;
  v_rows jsonb;
begin
  if v_uid is null then raise exception 'Login required.';end if;
  perform public.rr_assert_active_user_v1();
  select * into v_profile
  from public.rr_user_profiles p
  where p.auth_user_id=v_uid and coalesce(p.is_active,false)
    and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
  order by p.updated_at desc nulls last limit 1;
  if not found then raise exception 'Active User Directory profile required.';end if;

  v_identity:=public.rr_upm_effective_identity_v200();
  v_worker:=public.rr_upm_current_worker_id_v9112();
  v_role:=upper(coalesce(v_identity->>'role_code',v_identity->>'resolved_role',v_profile.role_code,'WORKER'));
  v_global:=v_role in('OWNER','SUPER_ADMIN','ADMIN');
  v_costing:=v_role in('OWNER','SUPER_ADMIN','ADMIN','MANAGER');

  select coalesce(jsonb_agg(to_jsonb(q) order by q.sent_at desc),'[]'::jsonb)
  into v_rows
  from(
    select b.id,b.canonical_key,b.source_module,b.source_record_id,b.source_event_type,
      case when upper(coalesce(b.source_module,''))='UPM_RATE' then 'COSTING'
           else public.rr_real_chat_canonical_department_v83(b.department_code) end department_code,
      b.sender_worker_id,b.receiver_user_id,b.receiver_worker_id,
      case when public.rr_real_chat_canonical_state_v83(b.source_module,b.source_event_type,b.action_code,b.personal_payload)='CLOSE'
           then null else b.action_code end action_code,
      case when public.rr_real_chat_canonical_state_v83(b.source_module,b.source_event_type,b.action_code,b.personal_payload)='CLOSE'
           then null else b.action_label end action_label,
      public.rr_real_chat_canonical_state_v83(b.source_module,b.source_event_type,b.action_code,b.personal_payload) canonical_state,
      case
        when upper(coalesce(b.source_module,''))='UPM_RATE' and v_costing then b.personal_payload
        when v_global
          or b.receiver_user_id=v_uid
          or b.receiver_worker_id=v_worker
          or public.rr_canonical_worker_id_v264(b.receiver_worker_id)=v_worker
        then b.personal_payload else '{}'::jsonb end personal_payload,
      b.group_payload,b.deep_link,b.sent_at,
      (select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb)
       from public.rr_real_chat_receipts_v70 r
       where r.message_id=b.id and(v_global or r.receiver_user_id=v_uid)) rr_real_chat_receipts_v70
    from public.rr_real_chat_message_bridge_v70 b
    where b.archived_at is null
      and upper(coalesce(b.source_event_type,''))<>'ASSIGNMENT_RATE_UPDATED'
      and coalesce(b.canonical_key,'') not like 'UPM_ALTER_EVENT:%'
      and coalesce(b.canonical_key,'') not like 'UPM_ACTION:%'
      and(
        (upper(coalesce(b.source_module,''))='UPM_RATE' and v_costing)
        or(upper(coalesce(b.source_module,''))<>'UPM_RATE' and(
          v_global
          or b.receiver_user_id=v_uid
          or b.receiver_worker_id=v_worker
          or public.rr_canonical_worker_id_v264(b.receiver_worker_id)=v_worker
          or exists(
            select 1 from public.rr_real_chat_department_membership_v70 m
            where m.worker_id=v_worker and m.is_active
              and public.rr_real_chat_canonical_department_v83(m.department_code)=
                  public.rr_real_chat_canonical_department_v83(b.department_code)
          )
        ))
      )
    order by b.sent_at desc
    limit least(greatest(coalesce(p_limit,2000),1),5000)
  )q;
  return v_rows;
end
$function$;

revoke all on function public.rr_real_chat_conversation_history_v83(integer) from public,anon;
grant execute on function public.rr_real_chat_conversation_history_v83(integer) to authenticated;

-- A retry by the same selected receiver is a successful no-op.  A different
-- receiver remains rejected.  This removes the post-refresh warning loop and
-- keeps exactly one audit row.
create or replace function public.rr_upm_accept_submit_v794(p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  q public.rr_upm_submit_requests_v794%rowtype;
  v_ctx jsonb:=public.rr_upm_effective_identity_v200();
  v_worker uuid:=public.rr_upm_current_worker_id_v9112();
  v_auth uuid:=nullif(v_ctx->>'effective_auth_user_id','')::uuid;
  v_selected boolean;
begin
  select * into q from public.rr_upm_submit_requests_v794 where id=p_request_id for update;
  if not found then raise exception 'Submit handover not found.';end if;

  v_selected:=q.selected_receiver_worker_id is not distinct from v_worker
           or q.selected_receiver_auth_id is not distinct from v_auth;
  if not v_selected then
    raise exception 'Only the selected receiver can Accept & Count this handover.';
  end if;

  if q.accepted_lm_id is not null
     or upper(coalesce(q.status,'')) in('LM_ACCEPTED','LM_COUNTED','DISPUTED','COMPLETED') then
    if q.accepted_lm_id is distinct from v_worker
       and q.accepted_lm_id is distinct from v_auth then
      raise exception 'This handover was accepted by another receiver.';
    end if;
    return jsonb_build_object(
      'ok',true,'version','V330_IDEMPOTENT_RECEIVER_ACCEPT','request_id',q.id,
      'duplicate_blocked',true,'audit_inserted',false,'status',q.status,
      'colour_rows',q.colour_rows,'assigned_total',q.assigned_total,
      'worker_ready_total',q.worker_ready_total,'receiver_name',q.selected_receiver_name,
      'receiver_role',q.selected_receiver_role
    );
  end if;

  if q.status not in('WAITING_LM','ESCALATED') then
    raise exception 'This handover is no longer available.';
  end if;

  update public.rr_upm_submit_requests_v794
  set status='LM_ACCEPTED',accepted_lm_id=coalesce(v_auth,v_worker),
      accepted_lm_name=q.selected_receiver_name,accepted_at=now(),updated_at=now()
  where id=q.id;

  update public.rr_upm_submit_lm_candidates_v794
  set response_status=case when line_man_id=coalesce(v_auth,v_worker) then 'ACCEPTED' else 'CLOSED' end,
      response_at=now()
  where request_id=q.id;

  insert into public.rr_upm_submit_audit_v794(request_id,action_code,actor_name,details)
  values(q.id,'RECEIVER_ACCEPTED',q.selected_receiver_name,jsonb_build_object(
    'effective_worker_id',v_worker,'receiver_role',q.selected_receiver_role,
    'action_id','SUBMIT_ACCEPT:'||q.id::text
  ));

  return jsonb_build_object(
    'ok',true,'version','V330_IDEMPOTENT_RECEIVER_ACCEPT','request_id',q.id,
    'duplicate_blocked',false,'audit_inserted',true,'status','LM_ACCEPTED',
    'colour_rows',q.colour_rows,'assigned_total',q.assigned_total,
    'worker_ready_total',q.worker_ready_total,'receiver_name',q.selected_receiver_name,
    'receiver_role',q.selected_receiver_role
  );
end
$function$;

revoke all on function public.rr_upm_accept_submit_v794(uuid) from public,anon;
grant execute on function public.rr_upm_accept_submit_v794(uuid) to authenticated,service_role;

-- The existing responsibility writer now reuses the same recovery event for
-- the same journey/giver/receiver/quantity.  Historical duplicates remain in
-- audit storage; no real business row is deleted.
create or replace function public.rr_upm_responsibility_offer_v800(
  p_event_type text,p_canonical_lot_id text,p_lot_no text,p_department_code text,
  p_assignment_id text,p_colour_code text,p_size_code text,p_qty numeric,
  p_giver_worker_id text,p_giver_name text,p_receiver_worker_id text,p_receiver_name text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_type text:=upper(trim(coalesce(p_event_type,'')));
  v_gate jsonb;
  v_id uuid;
  v_code text;
  v_msg text;
  v_existing record;
  v_performer text;
  v_identity jsonb:=public.rr_upm_effective_identity_v200();
  v_payload jsonb;
begin
  if v_type not in('ASSIGN_HANDOVER','SUBMIT_COUNT_HANDOVER','MISSING_RECOVERY_HANDOVER','ALTER_RECOVERY_HANDOVER') then
    raise exception 'Unsupported responsibility event type %',v_type;
  end if;
  if nullif(trim(p_receiver_worker_id),'') is null then raise exception 'Receiver worker required.';end if;

  if v_type='MISSING_RECOVERY_HANDOVER'
     and nullif(p_payload->>'missing_id','') is not null
     and nullif(p_payload->>'recovery_journey_id','') is not null then
    select e.id,e.event_code,e.status into v_existing
    from public.rr_upm_responsibility_events_v800 e
    where e.event_type=v_type
      and e.payload->>'missing_id'=p_payload->>'missing_id'
      and e.payload->>'recovery_journey_id'=p_payload->>'recovery_journey_id'
      and coalesce(e.giver_worker_id,'')=coalesce(p_giver_worker_id,'')
      and coalesce(e.receiver_worker_id,'')=coalesce(p_receiver_worker_id,'')
      and coalesce(e.qty,0)=coalesce(p_qty,0)
      and upper(coalesce(e.status,'')) not in('REFUSED','REJECTED','CANCELLED','VOID')
    order by e.created_at desc limit 1;
    if found then
      return jsonb_build_object(
        'ok',true,'event_id',v_existing.id,'event_code',v_existing.event_code,
        'status',v_existing.status,'receiver_worker_id',p_receiver_worker_id,
        'duplicate_blocked',true,'message','Existing recovery handover reused.'
      );
    end if;
  end if;

  if v_type='ASSIGN_HANDOVER' then
    v_gate:=public.rr_upm_worker_new_work_gate_v800(p_receiver_worker_id);
    if not coalesce((v_gate->>'allowed')::boolean,false) then
      raise exception 'NEW WORK BLOCKED: previous submit/count/handover confirmation pending for worker %',p_receiver_worker_id;
    end if;
  end if;

  select coalesce(p.full_name,auth.uid()::text) into v_performer
  from public.rr_user_profiles p
  where p.auth_user_id=auth.uid() and p.is_active
  order by p.updated_at desc nulls last limit 1;
  v_performer:=coalesce(v_performer,auth.uid()::text,'SYSTEM');
  v_payload:=coalesce(p_payload,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object(
    'performed_by_auth_user_id',auth.uid(),
    'performed_by_name',v_performer,
    'act_as_worker_id',case when coalesce((v_identity->>'on_behalf')::boolean,false) then v_identity->>'worker_id' end,
    'act_as_name',case when coalesce((v_identity->>'on_behalf')::boolean,false) then v_identity->>'display_name' end
  ));

  v_code:=public.rr_v800_code('RESP');
  insert into public.rr_upm_responsibility_events_v800(
    event_code,event_type,canonical_lot_id,lot_no,department_code,assignment_id,
    colour_code,size_code,qty,giver_worker_id,giver_name,receiver_worker_id,
    receiver_name,status,giver_confirmed_at,payload
  ) values(
    v_code,v_type,p_canonical_lot_id,p_lot_no,upper(p_department_code),p_assignment_id,
    upper(p_colour_code),upper(p_size_code),coalesce(p_qty,0),p_giver_worker_id,p_giver_name,
    p_receiver_worker_id,p_receiver_name,'GIVER_CONFIRMED',now(),v_payload
  ) returning id into v_id;

  v_msg:=case v_type
    when 'ASSIGN_HANDOVER' then format('NEW WORK OFFER · Lot %s · %s %s · Qty %s · %s. Accept confirmation required before responsibility starts.',coalesce(p_lot_no,'—'),coalesce(upper(p_colour_code),'—'),coalesce(upper(p_size_code),'ALL'),coalesce(p_qty,0),coalesce(upper(p_department_code),'—'))
    when 'SUBMIT_COUNT_HANDOVER' then format('SUBMIT COUNT CONFIRMATION · Lot %s · %s %s · Qty %s. Receiver count/accept required before responsibility closes.',coalesce(p_lot_no,'—'),coalesce(upper(p_colour_code),'—'),coalesce(upper(p_size_code),'ALL'),coalesce(p_qty,0))
    when 'MISSING_RECOVERY_HANDOVER' then format('MISSING RECOVERY HANDOVER · Lot %s · %s %s · Qty %s. Physical recovery acceptance required.',coalesce(p_lot_no,'—'),coalesce(upper(p_colour_code),'—'),coalesce(upper(p_size_code),'—'),coalesce(p_qty,0))
    else format('ALTER RECOVERY HANDOVER · Lot %s · %s %s · Qty %s. Physical acceptance required.',coalesce(p_lot_no,'—'),coalesce(upper(p_colour_code),'—'),coalesce(upper(p_size_code),'—'),coalesce(p_qty,0))
  end;

  insert into public.rr_upm_message_outbox_v800(
    message_code,event_id,worker_id,recipient_name,channel,message_type,message_text
  ) values
    (public.rr_v800_code('MSG'),v_id,p_receiver_worker_id,p_receiver_name,'IN_APP',v_type,v_msg),
    (public.rr_v800_code('WA'),v_id,p_receiver_worker_id,p_receiver_name,'WHATSAPP',v_type,v_msg);

  return jsonb_build_object(
    'ok',true,'event_id',v_id,'event_code',v_code,'status','GIVER_CONFIRMED',
    'receiver_worker_id',p_receiver_worker_id,'duplicate_blocked',false,'message',v_msg
  );
end
$function$;

-- Low-level writer is internal. Authenticated clients use the authorized
-- assignment/submit/recovery RPCs which call it under their existing engines.
revoke all on function public.rr_upm_responsibility_offer_v800(text,text,text,text,text,text,text,numeric,text,text,text,text,jsonb)
from public,anon,authenticated;
grant execute on function public.rr_upm_responsibility_offer_v800(text,text,text,text,text,text,text,numeric,text,text,text,text,jsonb)
to service_role;

-- Legacy recovery entry remains the UI entry point, but now validates the
-- effective actor and reuses an existing handover for retry/double tap.
create or replace function public.rr_upm_missing_found_start_v215(
  p_missing_id uuid,p_found_qty numeric,p_found_department_code text,
  p_found_worker_id text,p_found_name text,p_remarks text default null
) returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  m public.rr_upm_missing_qty_v800%rowtype;
  c public.rr_upm_colour_custody_v204%rowtype;
  v_found record;
  v_existing record;
  v_effective_worker uuid:=public.rr_upm_current_worker_id_v9112();
  v_role text:=upper(coalesce(public.rr_upm_effective_role_v200(),''));
  v_j uuid;
  v_seq integer;
  v_offer jsonb;
  v_event uuid;
begin
  select * into m from public.rr_upm_missing_qty_v800 where id=p_missing_id for update;
  if not found then raise exception 'Missing Qty record not found.';end if;
  if upper(coalesce(m.status,'')) not in('WORKER_CLAIM_PENDING','RECOVERY_JOURNEY') then
    raise exception 'Missing journey is closed: %',m.status;
  end if;

  select w.worker_id,w.worker_name,w.linked_auth_user_id into v_found
  from public.rr_worker_directory_unified_v1 w
  where w.is_active and(w.worker_id::text=p_found_worker_id or w.linked_auth_user_id::text=p_found_worker_id)
  order by(w.worker_id::text=p_found_worker_id) desc limit 1;
  if not found then raise exception 'Found-by worker mapping required.';end if;
  if v_role not in('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','CUTTING_MASTER')
     and v_found.worker_id is distinct from v_effective_worker then
    raise exception 'Only the effective found-by worker or authorized staff can start recovery.';
  end if;
  if coalesce(p_found_qty,0)<=0 or p_found_qty>m.missing_qty then
    raise exception 'Found Qty must be >0 and <= Missing Qty %',m.missing_qty;
  end if;

  select * into c
  from public.rr_upm_colour_custody_v204
  where canonical_lot_id=m.canonical_lot_id and upper(colour_code)=upper(m.colour_code)
  limit 1;
  if not found or c.current_custodian_worker_id is null then
    raise exception 'Current physical custody not resolved for Lot/Colour.';
  end if;

  select e.id,e.responsibility_event_id,e.status,e.recovery_journey_id into v_existing
  from public.rr_upm_missing_recovery_events_v215 e
  where e.missing_id=m.id
    and e.event_type='FOUND_HANDOVER'
    and coalesce(e.giver_worker_id,'') in(v_found.worker_id::text,coalesce(v_found.linked_auth_user_id::text,''))
    and coalesce(e.receiver_worker_id,'')=c.current_custodian_worker_id::text
    and coalesce(e.qty,0)=coalesce(p_found_qty,0)
    and upper(coalesce(e.status,'')) not in('REFUSED','REJECTED','CANCELLED','VOID')
  order by e.created_at desc limit 1;
  if found then
    return jsonb_build_object(
      'ok',true,'missing_id',m.id,'recovery_journey_id',v_existing.recovery_journey_id,
      'responsibility_event_id',v_existing.responsibility_event_id,
      'duplicate_blocked',true,'status',v_existing.status,
      'target_worker_id',c.current_custodian_worker_id,'target_name',c.current_custodian_name
    );
  end if;

  v_j:=coalesce(m.recovery_journey_id,gen_random_uuid());
  update public.rr_upm_missing_qty_v800
  set status='RECOVERY_JOURNEY',recovery_journey_id=v_j,
      payload=coalesce(payload,'{}')||jsonb_build_object(
        'found_qty',p_found_qty,'found_department_code',upper(p_found_department_code),
        'found_worker_id',v_found.worker_id,'found_name',v_found.worker_name,
        'target_custodian_worker_id',c.current_custodian_worker_id,
        'target_custodian_name',c.current_custodian_name,'target_custody_stage',c.custody_stage
      ),updated_at=now()
  where id=m.id;

  select coalesce(max(sequence_no),0)+1 into v_seq
  from public.rr_upm_missing_recovery_events_v215 where recovery_journey_id=v_j;
  v_offer:=public.rr_upm_responsibility_offer_v800(
    'MISSING_RECOVERY_HANDOVER',m.canonical_lot_id,m.lot_no,upper(p_found_department_code),
    m.assignment_id,m.colour_code,m.size_code,p_found_qty,
    v_found.worker_id::text,v_found.worker_name,c.current_custodian_worker_id::text,c.current_custodian_name,
    jsonb_build_object('missing_id',m.id,'recovery_journey_id',v_j,'sequence_no',v_seq,'target_custody_stage',c.custody_stage)
  );
  v_event:=(v_offer->>'event_id')::uuid;
  insert into public.rr_upm_missing_recovery_events_v215(
    missing_id,recovery_journey_id,sequence_no,event_type,from_department_code,to_department_code,
    giver_worker_id,giver_name,receiver_worker_id,receiver_name,qty,responsibility_event_id,status,remarks,payload
  ) values(
    m.id,v_j,v_seq,'FOUND_HANDOVER',upper(p_found_department_code),m.department_code,
    v_found.worker_id::text,v_found.worker_name,c.current_custodian_worker_id::text,c.current_custodian_name,
    p_found_qty,v_event,'OFFERED',p_remarks,jsonb_build_object('target_custody_stage',c.custody_stage)
  );
  return jsonb_build_object(
    'ok',true,'missing_id',m.id,'recovery_journey_id',v_j,'sequence_no',v_seq,
    'responsibility_event_id',v_event,'duplicate_blocked',false,
    'target_worker_id',c.current_custodian_worker_id,'target_name',c.current_custodian_name,
    'status','AWAITING_PHYSICAL_ACCEPT'
  );
end
$function$;

create or replace function public.rr_upm_missing_recovery_forward_v227(
  p_missing_id uuid,p_to_department_code text,p_to_worker_id text,p_to_worker_name text,
  p_remarks text default null
) returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  m public.rr_upm_missing_qty_v800%rowtype;
  v_target record;
  v_existing record;
  v_effective_worker uuid:=public.rr_upm_current_worker_id_v9112();
  v_role text:=upper(coalesce(public.rr_upm_effective_role_v200(),''));
  v_j uuid;
  v_seq integer;
  v_qty numeric;
  v_event jsonb;
  v_event_id uuid;
begin
  select * into m from public.rr_upm_missing_qty_v800 where id=p_missing_id for update;
  if not found then raise exception 'Recovery not found.';end if;
  v_qty:=coalesce(m.recovery_pending_qty,0);
  if v_qty<=0 then raise exception 'No Found PCS in recovery.';end if;
  if nullif(m.recovery_current_worker_id,'') is null then raise exception 'Current recovery custodian missing.';end if;
  if v_role not in('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN')
     and not exists(
       select 1 from public.rr_worker_directory_unified_v1 w
       where w.worker_id=v_effective_worker
         and(w.worker_id::text=m.recovery_current_worker_id or w.linked_auth_user_id::text=m.recovery_current_worker_id)
     ) then
    raise exception 'Only the current recovery custodian or authorized staff can forward recovery.';
  end if;
  select w.worker_id,w.worker_name,w.linked_auth_user_id into v_target
  from public.rr_worker_directory_unified_v1 w
  where w.is_active and(w.worker_id::text=p_to_worker_id or w.linked_auth_user_id::text=p_to_worker_id)
  order by(w.worker_id::text=p_to_worker_id) desc limit 1;
  if not found then raise exception 'Recovery receiver mapping required.';end if;

  select e.responsibility_event_id,e.status into v_existing
  from public.rr_upm_missing_recovery_events_v215 e
  where e.missing_id=m.id and e.event_type='RECOVERY_HANDOVER'
    and coalesce(e.giver_worker_id,'')=coalesce(m.recovery_current_worker_id,'')
    and coalesce(e.receiver_worker_id,'') in(v_target.worker_id::text,coalesce(v_target.linked_auth_user_id::text,''))
    and coalesce(e.qty,0)=v_qty
    and upper(coalesce(e.status,'')) not in('REFUSED','REJECTED','CANCELLED','VOID')
  order by e.created_at desc limit 1;
  if found then
    return jsonb_build_object('ok',true,'missing_id',m.id,
      'responsibility_event_id',v_existing.responsibility_event_id,'qty',v_qty,
      'next_owner',v_target.worker_name,'duplicate_blocked',true,'status',v_existing.status);
  end if;

  v_j:=m.recovery_journey_id;
  select coalesce(max(sequence_no),0)+1 into v_seq
  from public.rr_upm_missing_recovery_events_v215 where recovery_journey_id=v_j;
  v_event:=public.rr_upm_responsibility_offer_v800(
    'MISSING_RECOVERY_HANDOVER',m.canonical_lot_id,m.lot_no,m.recovery_current_department,
    m.assignment_id,m.colour_code,m.size_code,v_qty,m.recovery_current_worker_id,
    m.recovery_current_worker_name,v_target.worker_id::text,v_target.worker_name,
    jsonb_build_object('missing_id',m.id,'recovery_journey_id',v_j,'sequence_no',v_seq,'to_department_code',upper(p_to_department_code))
  );
  v_event_id:=(v_event->>'event_id')::uuid;
  insert into public.rr_upm_missing_recovery_events_v215(
    missing_id,recovery_journey_id,sequence_no,event_type,from_department_code,to_department_code,
    giver_worker_id,giver_name,receiver_worker_id,receiver_name,qty,responsibility_event_id,status,remarks,payload
  ) values(
    m.id,v_j,v_seq,'RECOVERY_HANDOVER',m.recovery_current_department,upper(p_to_department_code),
    m.recovery_current_worker_id,m.recovery_current_worker_name,v_target.worker_id::text,v_target.worker_name,
    v_qty,v_event_id,'OFFERED',p_remarks,'{}'
  );
  return jsonb_build_object('ok',true,'missing_id',m.id,'responsibility_event_id',v_event_id,
    'qty',v_qty,'from_department',m.recovery_current_department,'to_department',upper(p_to_department_code),
    'next_owner',v_target.worker_name,'duplicate_blocked',false,'status','AWAITING_NEXT_ACCEPT');
end
$function$;

create or replace function public.rr_upm_missing_recovery_offer_current_receiver_v228(
  p_missing_id uuid,p_remarks text default null
) returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  m public.rr_upm_missing_qty_v800%rowtype;
  c public.rr_upm_colour_custody_v204%rowtype;
  v_existing record;
  v_effective_worker uuid:=public.rr_upm_current_worker_id_v9112();
  v_role text:=upper(coalesce(public.rr_upm_effective_role_v200(),''));
  v_seq integer;
  v_event jsonb;
  v_event_id uuid;
begin
  select * into m from public.rr_upm_missing_qty_v800 where id=p_missing_id for update;
  if not found then raise exception 'Recovery not found.';end if;
  if coalesce(m.recovery_pending_qty,0)<=0 then raise exception 'No recovery PCS pending.';end if;
  if v_role not in('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN')
     and not exists(
       select 1 from public.rr_worker_directory_unified_v1 w
       where w.worker_id=v_effective_worker
         and(w.worker_id::text=m.recovery_current_worker_id or w.linked_auth_user_id::text=m.recovery_current_worker_id)
     ) then
    raise exception 'Only the current recovery custodian or authorized staff can offer recovery.';
  end if;
  select * into c from public.rr_upm_colour_custody_v204
  where canonical_lot_id=m.canonical_lot_id and upper(colour_code)=upper(m.colour_code) limit 1;
  if not found or c.pending_receiver_worker_id is null then raise exception 'Current mapped receiver not found.';end if;

  select e.responsibility_event_id,e.status into v_existing
  from public.rr_upm_missing_recovery_events_v215 e
  where e.missing_id=m.id
    and e.receiver_worker_id=c.pending_receiver_worker_id::text
    and coalesce(e.qty,0)=coalesce(m.recovery_pending_qty,0)
    and upper(coalesce(e.status,'')) not in('REFUSED','REJECTED','CANCELLED','VOID')
  order by e.created_at desc limit 1;
  if found then
    return jsonb_build_object('ok',true,'missing_id',m.id,'qty',m.recovery_pending_qty,
      'giver',m.recovery_current_worker_name,'receiver',c.pending_receiver_name,
      'responsibility_event_id',v_existing.responsibility_event_id,
      'duplicate_blocked',true,'status',v_existing.status);
  end if;

  select coalesce(max(sequence_no),0)+1 into v_seq
  from public.rr_upm_missing_recovery_events_v215 where recovery_journey_id=m.recovery_journey_id;
  v_event:=public.rr_upm_responsibility_offer_v800(
    'MISSING_RECOVERY_HANDOVER',m.canonical_lot_id,m.lot_no,m.recovery_current_department,
    m.assignment_id,m.colour_code,m.size_code,m.recovery_pending_qty,m.recovery_current_worker_id,
    m.recovery_current_worker_name,c.pending_receiver_worker_id::text,c.pending_receiver_name,
    jsonb_build_object('missing_id',m.id,'recovery_journey_id',m.recovery_journey_id,'auto_merge_same_stage',true)
  );
  v_event_id:=(v_event->>'event_id')::uuid;
  insert into public.rr_upm_missing_recovery_events_v215(
    missing_id,recovery_journey_id,sequence_no,event_type,from_department_code,to_department_code,
    giver_worker_id,giver_name,receiver_worker_id,receiver_name,qty,responsibility_event_id,status,remarks,payload
  ) values(
    m.id,m.recovery_journey_id,v_seq,'RECOVERY_TO_CURRENT_RECEIVER',m.recovery_current_department,
    m.recovery_current_department,m.recovery_current_worker_id,m.recovery_current_worker_name,
    c.pending_receiver_worker_id::text,c.pending_receiver_name,m.recovery_pending_qty,v_event_id,
    'OFFERED',p_remarks,jsonb_build_object('auto_merge_same_stage',true)
  );
  return jsonb_build_object('ok',true,'missing_id',m.id,'qty',m.recovery_pending_qty,
    'giver',m.recovery_current_worker_name,'receiver',c.pending_receiver_name,
    'responsibility_event_id',v_event_id,'duplicate_blocked',false,'status','AWAITING_RECEIVER_ACCEPT');
end
$function$;

revoke all on function public.rr_upm_missing_found_start_v215(uuid,numeric,text,text,text,text) from public,anon;
revoke all on function public.rr_upm_missing_recovery_forward_v227(uuid,text,text,text,text) from public,anon;
revoke all on function public.rr_upm_missing_recovery_offer_current_receiver_v228(uuid,text) from public,anon;
grant execute on function public.rr_upm_missing_found_start_v215(uuid,numeric,text,text,text,text) to authenticated;
grant execute on function public.rr_upm_missing_recovery_forward_v227(uuid,text,text,text,text) to authenticated;
grant execute on function public.rr_upm_missing_recovery_offer_current_receiver_v228(uuid,text) to authenticated;

-- One canonical recovery journey is returned to authorized participants.
-- Superseded retry rows remain auditable via audit_event_count but are not
-- rendered as competing live events.
create or replace function public.rr_upm_missing_recovery_journey_v215(p_missing_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $function$
declare
  m public.rr_upm_missing_qty_v800%rowtype;
  a record;
  r record;
  d record;
  e record;
  v_identity jsonb:=public.rr_upm_effective_identity_v200();
  v_worker uuid:=public.rr_upm_current_worker_id_v9112();
  v_role text;
  v_allowed boolean:=false;
  v_events jsonb:='[]'::jsonb;
  v_audit_count integer:=0;
  v_event_count integer:=0;
  v_operational jsonb:='{}'::jsonb;
  v_expected numeric:=0;
  v_accepted numeric:=0;
  v_found numeric:=0;
  v_confirmed_short numeric:=0;
  v_recovery_pending numeric:=0;
  v_downstream numeric:=0;
begin
  if auth.uid() is null then raise exception 'Login required.';end if;
  select * into m from public.rr_upm_missing_qty_v800 where id=p_missing_id;
  if not found then raise exception 'Recovery journey not found.';end if;
  select * into a from public.rr_upm_work_assignments_v8 where id::text=m.assignment_id limit 1;
  select * into r from public.rr_upm_assignment_receipts_v9112 where assignment_id::text=m.assignment_id limit 1;
  select * into d from public.rr_upm_short_decisions_v226
  where missing_id=m.id order by created_at desc limit 1;
  select * into e from public.rr_upm_missing_recovery_events_v215
  where missing_id=m.id and upper(coalesce(status,''))<>'SUPERSEDED'
  order by created_at desc limit 1;

  v_role:=upper(coalesce(v_identity->>'role_code',v_identity->>'resolved_role','WORKER'));
  v_allowed:=v_role in('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN');
  if not v_allowed and v_worker is not null then
    select exists(
      select 1 from public.rr_worker_directory_unified_v1 w
      where w.worker_id=v_worker and(
        w.worker_id::text in(coalesce(m.worker_id,''),coalesce(a.worker_id::text,''),coalesce(e.giver_worker_id,''),coalesce(e.receiver_worker_id,''))
        or coalesce(w.linked_auth_user_id::text,'') in(coalesce(m.worker_id,''),coalesce(a.worker_id::text,''),coalesce(e.giver_worker_id,''),coalesce(e.receiver_worker_id,''))
      )
    ) into v_allowed;
  end if;
  if not v_allowed then raise exception 'Recovery journey is not authorized for this effective identity.';end if;

  if m.assignment_id~*'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    v_operational:=coalesce(public.rr_upm_assignment_operational_qty_v280(m.assignment_id::uuid),'{}'::jsonb);
  end if;
  v_expected:=coalesce(nullif(m.payload->>'expected_good_qty','')::numeric,r.expected_qty,a.assigned_qty,0);
  v_accepted:=coalesce(nullif(m.payload->>'received_good_qty','')::numeric,r.confirmed_qty,0);
  v_found:=coalesce(nullif(m.payload->>'found_qty','')::numeric,0);
  v_confirmed_short:=coalesce(nullif(m.payload->>'confirmed_short_qty','')::numeric,0);
  v_recovery_pending:=coalesce(m.recovery_pending_qty,0);
  v_downstream:=coalesce(nullif(v_operational->>'good_qty','')::numeric,v_accepted,0);

  select coalesce(jsonb_agg(to_jsonb(q) order by q.sequence_no,q.created_at),'[]'::jsonb),count(*)
  into v_events,v_event_count
  from(
    select distinct on(coalesce(x.responsibility_event_id::text,x.id::text)) x.*
    from public.rr_upm_missing_recovery_events_v215 x
    where x.missing_id=m.id and upper(coalesce(x.status,''))<>'SUPERSEDED'
    order by coalesce(x.responsibility_event_id::text,x.id::text),x.created_at desc
  )q;
  select count(*) into v_audit_count from public.rr_upm_missing_recovery_events_v215 x where x.missing_id=m.id;

  return jsonb_build_object(
    'ok',true,'version','V330_CANONICAL_RECOVERY_IDENTITY',
    'missing',to_jsonb(m),
    'identity',jsonb_strip_nulls(jsonb_build_object(
      'performer_name',d.decided_name,'performer_role',d.decided_role,
      'performed_action',case when d.id is not null then 'CONFIRM_SHORT' end,
      'act_as_name',null,'act_as_recorded',false,
      'assigner_worker_id',a.assigner_worker_id,'assigner_name',a.assigned_by_name,'assigner_role',a.assigner_role,
      'receiver_worker_id',e.receiver_worker_id,'receiver_name',e.receiver_name,
      'responsible_worker_id',m.payload->>'responsibility_owner_id',
      'responsible_name',coalesce(m.payload->>'responsibility_owner_name',m.worker_name),
      'responsible_role',coalesce(m.payload->>'responsibility_owner_type',m.responsibility_owner_type),
      'responsible_source','ASSIGN_RECEIPT_SOURCE_CUSTODIAN'
    )),
    'quantity_journey',jsonb_build_object(
      'source_expected_qty',v_expected,'accepted_qty',v_accepted,
      'difference_qty',greatest(v_expected-v_accepted,0),
      'found_qty',v_found,'confirmed_short_qty',v_confirmed_short,
      'recovery_pending_qty',v_recovery_pending,
      'current_downstream_good_qty',v_downstream,
      'downstream_after_pending_accept_qty',v_downstream+v_recovery_pending,
      'colour_code',m.colour_code,'resolution_status',m.status
    ),
    'events',v_events,'canonical_event_count',v_event_count,'audit_event_count',v_audit_count,
    'audit_note','Act As is never inferred when the historical source did not record it.'
  );
end
$function$;

revoke all on function public.rr_upm_missing_recovery_journey_v215(uuid) from public,anon;
grant execute on function public.rr_upm_missing_recovery_journey_v215(uuid) to authenticated;

-- Repair the existing V317 shared search projection.  A confirmed Fabrication
-- handover is CLOSE even while the worker's separate assignment remains
-- WORKING.  Missing cards expose distinct audit identities and quantities.
create or replace function public.rr_real_chat_work_search_v317(
  p_status text default 'WORKING',p_search text default null,
  p_department_code text default null,p_limit integer default 500
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $function$
declare
  b jsonb;
  cards jsonb;
  counts jsonb;
  want text:=upper(coalesce(p_status,'WORKING'));
begin
  b:=public.rr_real_chat_work_search_v14(want,p_search,p_department_code,p_limit);
  cards:=coalesce(b->'cards','[]'::jsonb);

  with raw_keys as(
    select ord,c,
      coalesce(
        nullif(c->>'assignment_id',''),
        case when coalesce(c->>'event_key','') like 'UPM_ASSIGNMENT:%'
             then nullif(regexp_replace(c->>'event_key','^UPM_ASSIGNMENT:',''),'') end,
        case when coalesce(c->>'canonical_key','') like 'UPM_ASSIGNMENT:%'
             then nullif(regexp_replace(c->>'canonical_key','^UPM_ASSIGNMENT:',''),'') end,
        nullif(c->>'original_record_id','')
      ) assignment_key,
      nullif(c->>'original_record_id','') record_key
    from jsonb_array_elements(cards) with ordinality z(c,ord)
  ),raw_cards as(
    select ord,c,
      case when assignment_key~*'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then assignment_key::uuid end assignment_id,
      case when record_key~*'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then record_key::uuid end record_id
    from raw_keys
  ),x as(
    select raw.ord,raw.c,a.id aid,a.status ast,r.status rst,r.confirmed_at,re.id eid,re.status est,
      m.id mid,m.payload mpayload,m.missing_qty,m.recovery_pending_qty,m.status missing_status,
      ma.assigned_by_name,ma.assigner_worker_id,ma.assigner_role,
      md.decided_name performer_name,md.decided_role performer_role,
      mr.receiver_worker_id recovery_receiver_id,mr.receiver_name recovery_receiver_name,
      op.j operational,
      case
        when raw.c->>'source_module'='UPM_CUSTODY'
         and coalesce(raw.c->>'event_key','') like 'UPM_FABRICATION_RECEIPT:%' then
          case when upper(coalesce(r.status,'')) in('PENDING','DISPUTED') then 'WORKING'
               when upper(coalesce(r.status,'')) in('CONFIRMED','CONFIRMED_SHORT','RESOLVED') then 'CLOSE'
               else upper(coalesce(raw.c->>'chat_status',raw.c->>'source_status','')) end
        when r.assignment_id is null then null
        when upper(r.status)='PENDING' then 'ACCEPT_PENDING'
        when upper(r.status)='CONFIRMED' and upper(a.status)='IN_PROGRESS' then 'WORKING'
        when upper(a.status)='COMPLETED' then 'CLOSE'
        else upper(a.status)
      end resolved
    from raw_cards raw
    left join public.rr_upm_work_assignments_v8 a on a.id=raw.assignment_id
    left join public.rr_upm_assignment_receipts_v9112 r on r.assignment_id=a.id
    left join lateral(
      select q.id,q.status from public.rr_upm_responsibility_events_v800 q
      where q.assignment_id=a.id::text and q.event_type='ASSIGN_HANDOVER'
      order by q.created_at desc limit 1
    )re on true
    left join public.rr_upm_missing_qty_v800 m
      on raw.c->>'source_module'='UPM_MISSING_CLAIM' and m.id=raw.record_id
    left join public.rr_upm_work_assignments_v8 ma on ma.id::text=m.assignment_id
    left join lateral(
      select q.decided_name,q.decided_role from public.rr_upm_short_decisions_v226 q
      where q.missing_id=m.id order by q.created_at desc limit 1
    )md on true
    left join lateral(
      select q.receiver_worker_id,q.receiver_name from public.rr_upm_missing_recovery_events_v215 q
      where q.missing_id=m.id and upper(coalesce(q.status,''))<>'SUPERSEDED'
      order by q.created_at desc limit 1
    )mr on true
    left join lateral(
      select public.rr_upm_assignment_operational_qty_v280(ma.id) j
    )op on ma.id is not null
  ),enriched as(
    select ord,
      (
        case
          when aid is null or rst is null then c
          when c->>'source_module'='UPM_CUSTODY'
           and coalesce(c->>'event_key','') like 'UPM_FABRICATION_RECEIPT:%' then
            (c-'actions')||jsonb_build_object(
              'assignment_id',aid,'assignment_status',ast,'receipt_status',rst,
              'resolved_work_state',resolved,'responsibility_event_id',eid,
              'source_status',rst,
              'message',case when resolved='CLOSE' then 'Worker receipt confirmed · Fabrication handover closed'
                             else 'Fabrication custody · worker receipt pending' end,
              'actions','[]'::jsonb,'requires_action',false
            )
          else(c-'actions')||jsonb_build_object(
            'assignment_id',aid,'assignment_status',ast,'receipt_status',rst,
            'resolved_work_state',resolved,'responsibility_event_id',eid,
            'source_status',case when resolved='ACCEPT_PENDING' then 'ASSIGNED'
                                 when resolved='WORKING' then 'WORKING'
                                 when resolved='CLOSE' then 'CLOSE'
                                 else c->>'source_status' end,
            'message',case when resolved='ACCEPT_PENDING' then coalesce(c->>'worker_name','Worker')||' को काम दिया · Accept बाकी'
                           when resolved='WORKING' then coalesce(c->>'worker_name','Worker')||' · काम जारी है'
                           else c->>'message' end,
            'actions',case when resolved='ACCEPT_PENDING' and eid is not null then jsonb_build_array(jsonb_build_object(
              'code','CONFIRM_RECEIVED_PCS','label','ACCEPT & COUNT','assignment_id',aid,
              'event_id',eid,'engine','rr_upm_accept_physical_count_batch_v802'
            )) else coalesce(c->'actions','[]'::jsonb) end
          )
        end
      )
      ||case
        when c->>'source_module'='UPM_SUBMIT_HANDOFF'
         and upper(coalesce(c->>'source_status','')) in('WAITING_LM','ESCALATED')
         and jsonb_array_length(coalesce(c->'actions','[]'::jsonb))=0 then
          jsonb_build_object('action_waiting','WAITING FOR '||upper(coalesce(c->>'receiver_name',c->>'worker_name','SELECTED LINE MAN'))||' RECEIPT','requires_action',false)
        else '{}'::jsonb end
      ||case when mid is not null then jsonb_strip_nulls(jsonb_build_object(
        'performed_by_name',performer_name,'performer_role',performer_role,
        'assigner_name',assigned_by_name,'assigner_worker_id',assigner_worker_id,'assigner_role',assigner_role,
        'receiver_name',recovery_receiver_name,'receiver_worker_id',recovery_receiver_id,
        'responsible_name',coalesce(mpayload->>'responsibility_owner_name',c->>'worker_name'),
        'responsible_worker_id',mpayload->>'responsibility_owner_id',
        'responsible_role',coalesce(mpayload->>'responsibility_owner_type',c->>'responsibility_owner_type'),
        'source_expected_qty',coalesce(nullif(mpayload->>'expected_good_qty','')::numeric,0),
        'accepted_qty',coalesce(nullif(mpayload->>'received_good_qty','')::numeric,0),
        'difference_qty',greatest(coalesce(nullif(mpayload->>'expected_good_qty','')::numeric,0)-coalesce(nullif(mpayload->>'received_good_qty','')::numeric,0),0),
        'found_qty',coalesce(nullif(mpayload->>'found_qty','')::numeric,0),
        'confirmed_short_qty',coalesce(nullif(mpayload->>'confirmed_short_qty','')::numeric,0),
        'recovery_pending_qty',coalesce(recovery_pending_qty,0),
        'current_downstream_good_qty',coalesce(nullif(operational->>'good_qty','')::numeric,0),
        'pending_downstream_good_qty',coalesce(nullif(operational->>'good_qty','')::numeric,0)+coalesce(recovery_pending_qty,0),
        'recovery_status',missing_status
      )) else '{}'::jsonb end card
    from x
  )
  select coalesce(jsonb_agg(card order by ord),'[]'::jsonb) into cards from enriched;

  select coalesce(jsonb_object_agg(d,n),'{}'::jsonb) into counts
  from(
    select coalesce(nullif(c->>'department_code',''),'UNKNOWN') d,count(*) n
    from jsonb_array_elements(cards)x(c) group by 1
  )s;

  return jsonb_set(
    jsonb_set(jsonb_set(b,'{version}',to_jsonb('V330_PURCHASE_FABRICATION_IDENTITY'::text),true),'{cards}',cards,true),
    '{department_counts}',counts,true
  );
end
$function$;

revoke all on function public.rr_real_chat_work_search_v317(text,text,text,integer) from public,anon;
grant execute on function public.rr_real_chat_work_search_v317(text,text,text,integer) to authenticated;

-- Reversible, clearly-labelled TEST fixture.  It projects one canonical
-- Purchase parent with OPEN/WORKING/CLOSE children and never writes Purchase
-- business tables.
create or replace function public.rr_test_checkpoint5_purchase_fixture_v330(
  p_action text,p_worker_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_role text;
  v_worker record;
  v_key constant text:='TEST71_CP5_PURCHASE_PERSONAL';
  v_payload jsonb;
begin
  select upper(coalesce(role_code,'')) into v_role
  from public.rr_user_profiles
  where auth_user_id=auth.uid() and is_active
  order by updated_at desc nulls last limit 1;
  if v_role not in('OWNER','SUPER_ADMIN') then raise exception 'TEST71 fixture requires signed-in Super Admin.';end if;

  if upper(trim(coalesce(p_action,'')))='CLEANUP' then
    delete from public.rr_real_chat_message_bridge_v70 where canonical_key=v_key and data_mode='TEST';
    return jsonb_build_object('ok',true,'action','CLEANUP','canonical_key',v_key);
  end if;
  if upper(trim(coalesce(p_action,'')))<>'SETUP' then raise exception 'Fixture action must be SETUP or CLEANUP.';end if;

  select w.worker_id,w.worker_name,w.linked_auth_user_id into v_worker
  from public.rr_worker_directory_unified_v1 w
  where w.worker_id=p_worker_id and w.is_active
    and exists(
      select 1 from public.rr_real_chat_department_membership_v70 m
      where m.worker_id=w.worker_id and m.is_active
        and public.rr_real_chat_canonical_department_v83(m.department_code)='PURCHASE'
    );
  if not found then raise exception 'Active Purchase staff fixture target required.';end if;

  v_payload:=jsonb_build_object(
    'conversation_type','PURCHASE','purchase_kind','REGULAR_CLOTH',
    'cb_no','TEST71-CP5','cb_code','TEST71-CP5','supplier','TEST71 E2E FIXTURE',
    'bill_no','TEST71-CP5','fabric_name','TEST ONLY — REVERSIBLE','quantity',3,
    'quantity_unit','KG','roll_count',1,'amount',0,'canonical_state','WORKING',
    'status','ACTIVE','message','TEST71 reversible Purchase lifecycle fixture',
    'sender_name',v_worker.worker_name,'receiver_name',v_worker.worker_name,
    'source_department_code','PURCHASE','receiver_department_code','PURCHASE',
    'cb_children',jsonb_build_array(
      jsonb_build_object('cb_unit_id','TEST71-CP5-OPEN','cb_code','TEST71-CP5-O','state','ART_DUE'),
      jsonb_build_object('cb_unit_id','TEST71-CP5-WORKING','cb_code','TEST71-CP5-W','state','READY_FOR_CUTTING'),
      jsonb_build_object('cb_unit_id','TEST71-CP5-CLOSE','cb_code','TEST71-CP5-C','state','RELEASED')
    ),
    'next_actions','[]'::jsonb,'fixture_label','TEST71 CHECKPOINT 5 — SAFE TO DELETE'
  );

  insert into public.rr_real_chat_message_bridge_v70(
    data_mode,canonical_key,source_module,source_record_id,source_event_type,department_code,
    sender_user_id,sender_worker_id,receiver_user_id,receiver_worker_id,
    action_code,action_label,personal_payload,group_payload,deep_link,sent_at,archived_at,projection_type
  ) values(
    'TEST',v_key,'CB_PURCHASE',v_key,'CREATE_CB_SUCCEEDED','PURCHASE',
    auth.uid(),v_worker.worker_id,v_worker.linked_auth_user_id,v_worker.worker_id,
    null,null,v_payload,v_payload,
    'test70-cb-purchase-real-chat-pilot.html?chat=group&department=PURCHASE',now(),null,'TEST_FIXTURE'
  ) on conflict(canonical_key) do update set
    data_mode='TEST',source_module=excluded.source_module,source_record_id=excluded.source_record_id,
    source_event_type=excluded.source_event_type,department_code=excluded.department_code,
    sender_user_id=excluded.sender_user_id,sender_worker_id=excluded.sender_worker_id,
    receiver_user_id=excluded.receiver_user_id,receiver_worker_id=excluded.receiver_worker_id,
    action_code=null,action_label=null,personal_payload=excluded.personal_payload,
    group_payload=excluded.group_payload,deep_link=excluded.deep_link,sent_at=now(),
    archived_at=null,archive_reason=null,projection_type='TEST_FIXTURE';
  return jsonb_build_object('ok',true,'action','SETUP','canonical_key',v_key,
    'worker_id',v_worker.worker_id,'worker_name',v_worker.worker_name,'states',jsonb_build_array('OPEN','WORKING','CLOSE'));
end
$function$;

-- Transactional retry proof: temporary rows and their trigger side-effects are
-- deliberately rolled back inside the RPC before it returns.
create or replace function public.rr_test_checkpoint5_accept_retry_v330()
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_actual_role text;
  v_ctx jsonb:=public.rr_upm_effective_identity_v200();
  v_worker uuid:=public.rr_upm_current_worker_id_v9112();
  v_auth uuid:=nullif(v_ctx->>'effective_auth_user_id','')::uuid;
  v_request uuid;
  v_first jsonb;
  v_second jsonb;
  v_audit_count integer:=0;
  v_result jsonb:='{}'::jsonb;
  v_persisted boolean;
begin
  select upper(coalesce(role_code,'')) into v_actual_role
  from public.rr_user_profiles where auth_user_id=auth.uid() and is_active
  order by updated_at desc nulls last limit 1;
  if v_actual_role not in('OWNER','SUPER_ADMIN') then raise exception 'TEST71 retry proof requires signed-in Super Admin.';end if;
  if v_worker is null then raise exception 'Select a Line Man with Act As before retry proof.';end if;

  begin
    insert into public.rr_upm_submit_requests_v794(
      canonical_lot_id,lot_no,department_code,worker_id,worker_auth_id,worker_name,
      assignment_ids,colour_rows,assigned_total,worker_ready_total,status,
      selected_receiver_worker_id,selected_receiver_auth_id,selected_receiver_name,
      selected_receiver_role,target_department_code,created_by
    ) values(
      'TEST71_CP5_FABRICATION_RETRY','TEST71-CP5','PRINTING',v_worker,v_auth,
      coalesce(v_ctx->>'display_name','TEST71 Line Man'),'{}'::uuid[],'[]'::jsonb,1,1,'WAITING_LM',
      v_worker,v_auth,coalesce(v_ctx->>'display_name','TEST71 Line Man'),
      coalesce(v_ctx->>'role_code','LINE MAN'),'FABRICATION',auth.uid()
    ) returning id into v_request;
    v_first:=public.rr_upm_accept_submit_v794(v_request);
    v_second:=public.rr_upm_accept_submit_v794(v_request);
    select count(*) into v_audit_count from public.rr_upm_submit_audit_v794
    where request_id=v_request and action_code='RECEIVER_ACCEPTED';
    v_result:=jsonb_build_object('first',v_first,'second',v_second,'audit_count',v_audit_count,'request_id',v_request);
    raise exception using errcode='P3301',message='TEST71_CP5_ROLLBACK';
  exception when sqlstate 'P3301' then
    if sqlerrm<>'TEST71_CP5_ROLLBACK' then raise;end if;
  end;
  select exists(select 1 from public.rr_upm_submit_requests_v794 where id=v_request) into v_persisted;
  return v_result||jsonb_build_object('rolled_back',not v_persisted,'persisted',v_persisted);
end
$function$;

create or replace function public.rr_test_checkpoint5_recovery_retry_v330()
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_actual_role text;
  v_missing uuid:=gen_random_uuid();
  v_journey uuid:=gen_random_uuid();
  v_giver uuid:=gen_random_uuid();
  v_receiver uuid:=gen_random_uuid();
  v_first jsonb;
  v_second jsonb;
  v_event_count integer:=0;
  v_outbox_count integer:=0;
  v_result jsonb:='{}'::jsonb;
  v_persisted boolean;
begin
  select upper(coalesce(role_code,'')) into v_actual_role
  from public.rr_user_profiles where auth_user_id=auth.uid() and is_active
  order by updated_at desc nulls last limit 1;
  if v_actual_role not in('OWNER','SUPER_ADMIN') then raise exception 'TEST71 retry proof requires signed-in Super Admin.';end if;
  begin
    v_first:=public.rr_upm_responsibility_offer_v800(
      'MISSING_RECOVERY_HANDOVER','TEST71_CP5_RECOVERY','TEST71-CP5','STITCHING',
      gen_random_uuid()::text,'C1','ALL',1,v_giver::text,'TEST71 CP5 GIVER',
      v_receiver::text,'TEST71 CP5 RECEIVER',
      jsonb_build_object('missing_id',v_missing,'recovery_journey_id',v_journey,'fixture_label','TEST71 CHECKPOINT 5')
    );
    v_second:=public.rr_upm_responsibility_offer_v800(
      'MISSING_RECOVERY_HANDOVER','TEST71_CP5_RECOVERY','TEST71-CP5','STITCHING',
      gen_random_uuid()::text,'C1','ALL',1,v_giver::text,'TEST71 CP5 GIVER',
      v_receiver::text,'TEST71 CP5 RECEIVER',
      jsonb_build_object('missing_id',v_missing,'recovery_journey_id',v_journey,'fixture_label','TEST71 CHECKPOINT 5')
    );
    select count(*) into v_event_count from public.rr_upm_responsibility_events_v800
    where payload->>'missing_id'=v_missing::text and payload->>'recovery_journey_id'=v_journey::text;
    select count(*) into v_outbox_count from public.rr_upm_message_outbox_v800
    where event_id=(v_first->>'event_id')::uuid;
    v_result:=jsonb_build_object('first',v_first,'second',v_second,
      'event_count',v_event_count,'outbox_count',v_outbox_count,'event_id',v_first->>'event_id');
    raise exception using errcode='P3302',message='TEST71_CP5_ROLLBACK';
  exception when sqlstate 'P3302' then
    if sqlerrm<>'TEST71_CP5_ROLLBACK' then raise;end if;
  end;
  select exists(select 1 from public.rr_upm_responsibility_events_v800 where id=(v_result->>'event_id')::uuid) into v_persisted;
  return v_result||jsonb_build_object('rolled_back',not v_persisted,'persisted',v_persisted);
end
$function$;

revoke all on function public.rr_test_checkpoint5_purchase_fixture_v330(text,uuid) from public,anon;
revoke all on function public.rr_test_checkpoint5_accept_retry_v330() from public,anon;
revoke all on function public.rr_test_checkpoint5_recovery_retry_v330() from public,anon;
grant execute on function public.rr_test_checkpoint5_purchase_fixture_v330(text,uuid) to authenticated;
grant execute on function public.rr_test_checkpoint5_accept_retry_v330() to authenticated;
grant execute on function public.rr_test_checkpoint5_recovery_retry_v330() to authenticated;

comment on function public.rr_real_chat_work_search_v317(text,text,text,integer) is
'TEST71 V330: canonical Purchase/Fabrication/Recovery mirror; Fabrication handover and worker assignment are distinct states.';
comment on function public.rr_upm_missing_recovery_journey_v215(uuid) is
'TEST71 V330: one canonical recovery event with separate performer, Act As, assigner, receiver and responsible identities.';

commit;
