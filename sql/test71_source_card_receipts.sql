-- Source-validated receipts for canonical UPM cards that have no action-inbox row.
-- This tracks actual viewing without replaying historical notifications or pushes.
create table if not exists rr_chat_notifications_test71.card_receipts(
 card_key text not null,recipient_id uuid not null,department_code text not null,
 source_card jsonb not null,actor_user_id uuid,delivered_at timestamptz,read_at timestamptz,
 primary key(card_key,recipient_id)
);
alter table rr_chat_notifications_test71.card_receipts enable row level security;
revoke all on rr_chat_notifications_test71.card_receipts from public,anon,authenticated;
create or replace function public.rr_chat_source_card_receipts_test71(
 p_department text,p_status text,p_worker uuid default null,p_read_keys text[] default '{}'
) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare dep text:=public.rr_real_chat_canonical_department_v83(p_department);cards jsonb;source jsonb;j jsonb;
 k text;keys text[]:='{}';recipients uuid[];assignment_ids uuid[];actor uuid;actor_at timestamptz;candidate record;role text;
begin
 perform public.rr_assert_active_user_v1();
 if upper(p_status) not in ('OPEN','WORKING','CLOSE') then raise exception 'Invalid status';end if;
 select upper(replace(coalesce(role_code,''),' ','_')) into role from public.rr_user_profiles where auth_user_id=auth.uid();
 if p_worker is null then
  if role not in('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MAN','LINE_MANAGER','CUTTING_MASTER','DEPARTMENT_HEAD') then raise exception 'Group access denied';end if;
  if role not in('OWNER','SUPER_ADMIN','ADMIN','MANAGER') and not exists(select 1 from public.rr_worker_directory_unified_v1 w join public.rr_real_chat_department_membership_v70 m on m.worker_id=w.worker_id where w.linked_auth_user_id=auth.uid() and m.is_active and public.rr_real_chat_canonical_department_v83(m.department_code)=dep) then raise exception 'Department access denied';end if;
  source:=public.rr_chat_department_projection_test71(dep,upper(p_status))->'cards';
 else
  if role not in('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MAN','LINE_MANAGER','CUTTING_MASTER','DEPARTMENT_HEAD') and not exists(select 1 from public.rr_worker_directory_unified_v1 w where w.worker_id=p_worker and w.linked_auth_user_id=auth.uid() and w.is_active) then raise exception 'Worker access denied';end if;
  source:=public.rr_real_chat_operational_work_v319(p_worker,upper(p_status),dep)->'cards';
 end if;
 if dep='FABRICATION' and p_worker is null and upper(p_status)='WORKING' then
 source:=coalesce(source,'[]')||coalesce((select jsonb_agg(x) from unnest(array['PRINTING','STICKER','METAL_ID','STITCHING','OVERLOCK','FOLDING','KAAJ_BUTTON','TEAK_TANKI','THREAD_CUT','QC','PRESS','PACKING']) d cross join lateral jsonb_array_elements(coalesce(public.rr_chat_department_projection_test71(d,'WORKING')->'cards','[]')) x
 where exists(select 1 from jsonb_array_elements(coalesce(x->'actions','[]')) action where upper(coalesce(action->>'code',action#>>'{}')) in('SUBMIT','CONFIRM_RECEIVED_PCS'))),'[]');
 end if;
 if upper(p_status)='WORKING' then
 source:=coalesce(source,'[]')||coalesce((select jsonb_agg(jsonb_build_object('event_key','ALTER:'||a.id,'canonical_lot_id',a.canonical_lot_id,'lot_no',a.lot_no,'department_code',dep,'worker_id',coalesce(a.responsible_id,a.karigar_id),'journey_id',a.id,'qty',a.open_qty,'source_status',a.stage,'event_at',a.updated_at,'source_actor_id',(select e.actor_id from public.rr_upm_alter_events_v740 e where e.journey_id=a.id order by e.created_at desc limit 1)))
 from public.rr_upm_alter_journey_v740 a where a.open_qty>0 and a.stage not like 'CLOSED%' and (dep='FABRICATION' or public.rr_real_chat_canonical_department_v83(a.responsible_department_code)=dep) and (p_worker is null or p_worker in(a.responsible_id,a.karigar_id,a.enrolled_lm_id))),'[]');
 source:=source||coalesce((select jsonb_agg(jsonb_build_object('event_key','RECTIFICATION:'||c.id,'canonical_lot_id',c.canonical_lot_id,'lot_no',c.lot_no,'department_code',dep,'worker_id',coalesce(c.assigned_worker_id,c.original_worker_id),'rectification_case_id',c.id,'qty',c.recalled_good_qty,'source_status',c.status,'event_at',c.assigned_at,'source_actor_id',c.created_by))
 from public.rr_upm_rectification_cases_v9101 c where c.status in('ASSIGNED','IN_PROGRESS') and (dep='FABRICATION' or public.rr_real_chat_canonical_department_v83(c.target_department_code)=dep) and (p_worker is null or p_worker in(c.assigned_worker_id,c.original_worker_id,c.line_man_id))),'[]');
 end if;
 -- Aggregate only colour assignments belonging to the same real lot/department/worker.
 -- A Fabrication ready-to-assign summary has no worker yet and uses one lot identity.
 with raw as(select x j,case when dep='FABRICATION' and upper(p_status)='OPEN' and exists(select 1 from jsonb_array_elements(coalesce(x->'actions','[]')) a where a->>'code'='ASSIGN_WORKER') then 'FAB:OPEN:LOT:'||(x->>'canonical_lot_id')
  when x->>'journey_id' is null and x->>'rectification_case_id' is null and x->>'worker_id' is not null and x->>'submit_request_id' is null then 'UPM_WORKER_LOT:'||upper(coalesce(x->>'canonical_lot_id',x->>'lot_no'))||'|'||upper(coalesce(x->>'department_code',dep))||'|'||(x->>'worker_id')
  else coalesce(x->>'event_key','PROJ709:'||coalesce(x->>'assignment_id',x->>'submit_request_id',x->>'lot_no')) end identity
  from jsonb_array_elements(coalesce(source,'[]')) x),grouped as(
  select identity,(jsonb_agg(raw.j order by raw.j->>'event_key')->0)||jsonb_build_object('event_key',identity,
   'source_event_keys',jsonb_agg(coalesce(raw.j->>'event_key','PROJ709:'||coalesce(raw.j->>'assignment_id',raw.j->>'submit_request_id',raw.j->>'lot_no')) order by raw.j->>'event_key'),
   'assignment_ids',coalesce(jsonb_agg(raw.j->'assignment_id' order by raw.j->>'assignment_id') filter(where raw.j->>'assignment_id' is not null),'[]'),
   'source_versions',jsonb_agg(jsonb_build_array(raw.j->>'event_key',raw.j->>'assignment_id',raw.j->>'submit_request_id',raw.j->>'source_status',raw.j->>'resolved_work_state',raw.j->>'receipt_status',raw.j->>'submit_status',raw.j->>'event_at',raw.j->>'qty') order by raw.j->>'event_key',raw.j->>'assignment_id')) j
  from raw group by identity)
 select coalesce(jsonb_agg(grouped.j),'[]') into cards from grouped;
 for j in select value from jsonb_array_elements(cards) loop
  k:='SOURCE_CARD_TEST71:'||md5(dep||upper(p_status)||(j->>'event_key')||(j->'source_versions')::text);keys:=array_append(keys,k);
  select coalesce(array_agg(value::uuid),'{}') into assignment_ids from jsonb_array_elements_text(j->'assignment_ids');
  actor:=null;actor_at:=null;
  select chosen.uid,chosen.at into actor,actor_at from (
   select nullif(j->>'source_actor_id','')::uuid uid,now() at union all select case when r.status in('CONFIRMED','CONFIRMED_SHORT') then r.confirmed_by else a.assigned_by end uid,
   coalesce(r.confirmed_at,a.assigned_at,a.created_at) at from public.rr_upm_work_assignments_v8 a left join public.rr_upm_assignment_receipts_v9112 r on r.assignment_id=a.id where a.id=any(assignment_ids)
   union all select case when q.status='WAITING_LM' then coalesce(q.created_by,q.worker_auth_id) else q.selected_receiver_auth_id end,
   coalesce(q.completed_at,q.worker_decided_at,q.counted_at,q.accepted_at,q.created_at) from public.rr_upm_submit_requests_v794 q where q.id::text=j->>'submit_request_id'
  ) chosen where chosen.uid is not null order by chosen.at desc nulls last limit 1;
  select array_agg(distinct w.linked_auth_user_id) into recipients from public.rr_worker_directory_unified_v1 w
  where w.is_active and upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE' and w.linked_auth_user_id is not null
   and (w.linked_auth_user_id=auth.uid() or upper(replace(coalesce(w.role_code,''),' ','_')) in('OWNER','SUPER_ADMIN','ADMIN')
    or w.worker_id::text=j->>'worker_id' or w.linked_auth_user_id=actor
    or exists(select 1 from public.rr_real_chat_department_membership_v70 m where m.worker_id=w.worker_id and m.is_active and public.rr_real_chat_canonical_department_v83(m.department_code)=dep));
  insert into rr_chat_notifications_test71.card_receipts(card_key,recipient_id,department_code,source_card,actor_user_id)
  select k,recipient,dep,j,actor from unnest(recipients) recipient on conflict(card_key,recipient_id) do nothing;
  update rr_chat_notifications_test71.card_receipts set delivered_at=coalesce(delivered_at,now()),read_at=case when k=any(p_read_keys) then coalesce(read_at,now()) else read_at end where card_key=k and recipient_id=auth.uid();
 end loop;
 -- Keys supplied by a client can update only its own currently authorized source cards.
 return (select coalesce(jsonb_agg(jsonb_build_object('action_key',own.card_key,'card_receipt',true,
  'event_key',own.source_card->>'event_key','source_event_keys',own.source_card->'source_event_keys',
  'assignment_ids',own.source_card->'assignment_ids','assignment_id',own.source_card->>'assignment_id',
  'submit_request_id',own.source_card->>'submit_request_id','lot_no',own.source_card->>'lot_no',
  'department_code',dep,'action_label','Card','actor_user_id',own.actor_user_id,
  'actor_name',(select min(w.worker_name) from public.rr_worker_directory_unified_v1 w where w.linked_auth_user_id=own.actor_user_id),
  'viewer_read_at',own.read_at,'viewer_is_recipient',true,'created_at',own.source_card->>'event_at',
  'route_url','?rc_status='||upper(p_status),'worker_ids',jsonb_build_array(own.source_card->>'worker_id'),
  'recipients',(select jsonb_agg(jsonb_build_object('recipient_id',r.recipient_id,
    'worker_name',(select min(w.worker_name) from public.rr_worker_directory_unified_v1 w where w.linked_auth_user_id=r.recipient_id),
    'role_code',(select min(w.role_code) from public.rr_worker_directory_unified_v1 w where w.linked_auth_user_id=r.recipient_id),
    'delivered_at',r.delivered_at,'read_at',r.read_at)) from rr_chat_notifications_test71.card_receipts r where r.card_key=own.card_key))),'[]')
  from rr_chat_notifications_test71.card_receipts own where own.card_key=any(keys) and own.recipient_id=auth.uid());
end $$;
revoke all on function public.rr_chat_source_card_receipts_test71(text,text,uuid,text[]) from public,anon;
grant execute on function public.rr_chat_source_card_receipts_test71(text,text,uuid,text[]) to authenticated;
