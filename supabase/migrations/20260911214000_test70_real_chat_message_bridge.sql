-- TEST70 Real Chat communication foundation. MAIN/REAL workflow rows are never mutated.
create table if not exists public.rr_real_chat_message_bridge_v70 (
  id uuid primary key default gen_random_uuid(),
  data_mode text not null default 'TEST' check (data_mode = 'TEST'),
  canonical_key text not null unique,
  source_module text not null,
  source_record_id text not null,
  source_event_type text not null,
  department_code text,
  sender_user_id uuid,
  sender_worker_id uuid,
  receiver_user_id uuid,
  receiver_worker_id uuid,
  action_code text,
  action_label text,
  personal_payload jsonb not null default '{}'::jsonb,
  group_payload jsonb not null default '{}'::jsonb,
  deep_link text not null,
  sent_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists rr_rc_bridge_sender_v70 on public.rr_real_chat_message_bridge_v70(sender_user_id, sent_at desc);
create index if not exists rr_rc_bridge_receiver_v70 on public.rr_real_chat_message_bridge_v70(receiver_user_id, sent_at desc);
create index if not exists rr_rc_bridge_worker_v70 on public.rr_real_chat_message_bridge_v70(receiver_worker_id, sent_at desc);
create index if not exists rr_rc_bridge_department_v70 on public.rr_real_chat_message_bridge_v70(department_code, sent_at desc);

create table if not exists public.rr_real_chat_receipts_v70 (
  message_id uuid not null references public.rr_real_chat_message_bridge_v70(id) on delete cascade,
  receiver_key text not null,
  receiver_user_id uuid,
  receiver_worker_id uuid,
  delivered_at timestamptz,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (message_id, receiver_key),
  check (receiver_user_id is not null or receiver_worker_id is not null),
  check (read_at is null or delivered_at is not null)
);
create index if not exists rr_rc_receipt_user_v70 on public.rr_real_chat_receipts_v70(receiver_user_id, read_at, delivered_at);
create index if not exists rr_rc_receipt_worker_v70 on public.rr_real_chat_receipts_v70(receiver_worker_id, read_at, delivered_at);

create table if not exists public.rr_real_chat_notification_links_v70 (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.rr_real_chat_message_bridge_v70(id) on delete cascade,
  receiver_key text not null,
  receiver_user_id uuid,
  receiver_worker_id uuid,
  source_notification_table text,
  source_notification_id uuid,
  deep_link text not null,
  created_at timestamptz not null default now(),
  unique(message_id, receiver_key)
);
create index if not exists rr_rc_notification_user_v70 on public.rr_real_chat_notification_links_v70(receiver_user_id, created_at desc);

create table if not exists public.rr_real_chat_action_registry_v70 (
  action_code text primary key,
  exact_button_label text not null,
  source_module text not null,
  source_page text not null,
  rpc_name text not null,
  allowed_roles text[] not null default '{}',
  opens_exact_card boolean not null default true,
  registry_status text not null check (registry_status in ('ACTIVE','AUDIT_PENDING','DISABLED')),
  notes text,
  updated_at timestamptz not null default now()
);

alter table public.rr_real_chat_message_bridge_v70 enable row level security;
alter table public.rr_real_chat_receipts_v70 enable row level security;
alter table public.rr_real_chat_notification_links_v70 enable row level security;
alter table public.rr_real_chat_action_registry_v70 enable row level security;

revoke all on public.rr_real_chat_message_bridge_v70 from anon, authenticated;
revoke all on public.rr_real_chat_receipts_v70 from anon, authenticated;
revoke all on public.rr_real_chat_notification_links_v70 from anon, authenticated;
revoke all on public.rr_real_chat_action_registry_v70 from anon, authenticated;
grant select on public.rr_real_chat_message_bridge_v70 to authenticated;
grant select on public.rr_real_chat_receipts_v70 to authenticated;
grant select on public.rr_real_chat_notification_links_v70 to authenticated;
grant select on public.rr_real_chat_action_registry_v70 to authenticated;

create or replace function public.rr_real_chat_is_global_staff_v70(p_user_id uuid)
returns boolean language sql stable security invoker set search_path = public
as $$
  select exists (
    select 1 from public.rr_user_profiles p
    where p.auth_user_id=p_user_id and p.is_active=true
      and coalesce(p.access_status,'ACTIVE')='ACTIVE'
      and upper(coalesce(p.role_code,'')) in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','ACCOUNTS','LINE_MANAGER','CUTTING_MASTER','PRINTING_OPERATOR','STICKER_OPERATOR')
  )
$$;

create policy rr_rc_bridge_select_v70 on public.rr_real_chat_message_bridge_v70
for select to authenticated using (
  (select auth.uid()) is not null and (
    (select auth.uid()) in (sender_user_id, receiver_user_id)
    or public.rr_real_chat_is_global_staff_v70((select auth.uid()))
  )
);
create policy rr_rc_receipt_select_v70 on public.rr_real_chat_receipts_v70
for select to authenticated using (
  (select auth.uid())=receiver_user_id
  or exists(select 1 from public.rr_real_chat_message_bridge_v70 m where m.id=message_id and m.sender_user_id=(select auth.uid()))
  or public.rr_real_chat_is_global_staff_v70((select auth.uid()))
);
create policy rr_rc_notification_select_v70 on public.rr_real_chat_notification_links_v70
for select to authenticated using (
  (select auth.uid())=receiver_user_id or public.rr_real_chat_is_global_staff_v70((select auth.uid()))
);
create policy rr_rc_registry_select_v70 on public.rr_real_chat_action_registry_v70
for select to authenticated using ((select auth.uid()) is not null);

create or replace function public.rr_real_chat_mark_receipt_v70(p_message_id uuid, p_event text)
returns public.rr_real_chat_receipts_v70
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_uid uuid := auth.uid(); v_row public.rr_real_chat_receipts_v70;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if upper(coalesce(p_event,'')) not in ('DELIVERED','READ') then raise exception 'INVALID_RECEIPT_EVENT'; end if;
  update public.rr_real_chat_receipts_v70 r
     set delivered_at=coalesce(r.delivered_at,now()),
         read_at=case when upper(p_event)='READ' then coalesce(r.read_at,now()) else r.read_at end,
         updated_at=now()
   where r.message_id=p_message_id and r.receiver_user_id=v_uid
   returning * into v_row;
  if not found then raise exception 'RECEIVER_MISMATCH'; end if;
  return v_row;
end $$;
revoke all on function public.rr_real_chat_mark_receipt_v70(uuid,text) from public, anon;
grant execute on function public.rr_real_chat_mark_receipt_v70(uuid,text) to authenticated;

create or replace function public.rr_real_chat_sync_upm_v70()
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_uid uuid:=auth.uid(); v_count integer;
begin
  if v_uid is null or not public.rr_real_chat_is_global_staff_v70(v_uid) then raise exception 'STAFF_ACCESS_REQUIRED'; end if;
  insert into public.rr_real_chat_message_bridge_v70(
    canonical_key,source_module,source_record_id,source_event_type,department_code,
    sender_user_id,receiver_user_id,receiver_worker_id,action_code,action_label,
    personal_payload,group_payload,deep_link,sent_at)
  select 'UPM_ASSIGNMENT:'||a.id,'UPM',a.id::text,'WORK_ASSIGNED',a.department_code,
    a.assigned_by,d.linked_auth_user_id,a.worker_id,'ASSIGN_WORKER','ASSIGN WORKER',
    jsonb_build_object('lot_no',a.lot_no,'colour_code',a.colour_code,'colour_name',a.colour_name,'assigned_qty',a.assigned_qty,'actual_rate',a.actual_rate,'status',a.status,'worker_name',a.worker_name_snapshot,'size_breakup',a.size_breakup),
    jsonb_build_object('lot_no',a.lot_no,'colour_name',a.colour_name,'assigned_qty',a.assigned_qty,'status',a.status,'worker_name',a.worker_name_snapshot),
    'test70-cb-purchase-real-chat-pilot.html?chat=personal&worker_id='||a.worker_id::text||'&message_key='||encode(convert_to('UPM_ASSIGNMENT:'||a.id,'UTF8'),'base64'),
    coalesce(a.assigned_at,a.created_at,now())
  from public.rr_upm_work_assignments_v8 a
  left join public.rr_worker_directory_unified_v1 d on d.worker_id=a.worker_id
  on conflict(canonical_key) do update set
    receiver_user_id=excluded.receiver_user_id,
    personal_payload=excluded.personal_payload,
    group_payload=excluded.group_payload,
    deep_link=excluded.deep_link;

  insert into public.rr_real_chat_receipts_v70(message_id,receiver_key,receiver_user_id,receiver_worker_id)
  select m.id,'WORKER:'||m.receiver_worker_id::text,m.receiver_user_id,m.receiver_worker_id
  from public.rr_real_chat_message_bridge_v70 m where m.source_module='UPM' and m.receiver_worker_id is not null
  on conflict(message_id,receiver_key) do update set receiver_user_id=excluded.receiver_user_id;

  insert into public.rr_real_chat_notification_links_v70(message_id,receiver_key,receiver_user_id,receiver_worker_id,deep_link)
  select m.id,'WORKER:'||m.receiver_worker_id::text,m.receiver_user_id,m.receiver_worker_id,m.deep_link
  from public.rr_real_chat_message_bridge_v70 m where m.source_module='UPM' and m.receiver_worker_id is not null
  on conflict(message_id,receiver_key) do update set receiver_user_id=excluded.receiver_user_id,deep_link=excluded.deep_link;
  get diagnostics v_count=row_count;
  return jsonb_build_object('ok',true,'notification_links_upserted',v_count);
end $$;
revoke all on function public.rr_real_chat_sync_upm_v70() from public, anon;
grant execute on function public.rr_real_chat_sync_upm_v70() to authenticated;

insert into public.rr_real_chat_action_registry_v70(action_code,exact_button_label,source_module,source_page,rpc_name,allowed_roles,registry_status,notes)
values
 ('ASSIGN_WORKER','ASSIGN WORKER','UPM','real-universal-production-v764-completed-hide.js','rr_upm_apply_actions_batch_v726',array['OWNER','ADMIN','MANAGER','LINE_MANAGER'],'ACTIVE','Exact source label verified'),
 ('ALTER_FILL','ALTER FILL','UPM','real-universal-production-v764-completed-hide.js','rr_upm_alter_stage_v740',array['OWNER','ADMIN','MANAGER','LINE_MANAGER'],'ACTIVE','Exact source label verified'),
 ('DAMAGE','DAMAGE','UPM','real-universal-production-v764-completed-hide.js','rr_upm_apply_actions_batch_v726',array['OWNER','ADMIN','MANAGER','LINE_MANAGER'],'ACTIVE','Exact source label verified'),
 ('SUBMIT','SUBMIT','UPM','real-universal-production-v764-completed-hide.js','rr_upm_submit_colours_v741',array['OWNER','ADMIN','MANAGER','LINE_MANAGER','WORKER'],'ACTIVE','Exact source label verified'),
 ('REMAKE_ISSUE','REMAKE ISSUE · CM','UPM','real-universal-production-v764-completed-hide.js','rr_upm_apply_actions_batch_v726',array['OWNER','ADMIN','CUTTING_MASTER'],'AUDIT_PENDING','Label verified; exact RPC branch contract requires role test'),
 ('RECEIVE_MASTER','RECEIVE MASTER · LM','UPM','real-universal-production-v764-completed-hide.js','rr_upm_apply_actions_batch_v726',array['OWNER','ADMIN','LINE_MANAGER'],'AUDIT_PENDING','Label verified; exact RPC branch contract requires role test'),
 ('DELIVER_KARIGAR','DELIVER KARIGAR · LM','UPM','real-universal-production-v764-completed-hide.js','rr_upm_apply_actions_batch_v726',array['OWNER','ADMIN','LINE_MANAGER'],'AUDIT_PENDING','Label verified; exact RPC branch contract requires role test'),
 ('RECEIVE_KARIGAR','RECEIVE KARIGAR · LM','UPM','real-universal-production-v764-completed-hide.js','rr_upm_apply_actions_batch_v726',array['OWNER','ADMIN','LINE_MANAGER'],'AUDIT_PENDING','Label verified; exact RPC branch contract requires role test')
on conflict(action_code) do update set exact_button_label=excluded.exact_button_label,source_module=excluded.source_module,source_page=excluded.source_page,rpc_name=excluded.rpc_name,allowed_roles=excluded.allowed_roles,registry_status=excluded.registry_status,notes=excluded.notes,updated_at=now();

comment on table public.rr_real_chat_message_bridge_v70 is 'TEST-only canonical communication projection; source workflow remains authoritative.';
comment on column public.rr_real_chat_receipts_v70.read_at is 'Only the exact receiver can set this through rr_real_chat_mark_receipt_v70; group reads never update it.';
