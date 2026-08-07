-- REAL FACTORY V797.6
-- MAIN SQL: Common in-app alert + manual WhatsApp + manual SMS combined flow.
-- TEST/REAL remain separated. This SQL never marks an external message DELIVERED.

begin;

create table if not exists public.rr_manual_contact_queue_v797_6(
  id uuid primary key default gen_random_uuid(),
  source_table text not null,
  source_id text not null,
  alert_code text not null,
  data_mode text not null default 'TEST',
  recipient_mobile text not null,
  intended_recipients jsonb not null default '[]'::jsonb,
  message_text text not null,
  whatsapp_url text not null,
  sms_url text not null,
  whatsapp_status text not null default 'READY_MANUAL',
  sms_status text not null default 'READY_MANUAL',
  whatsapp_opened_at timestamptz,
  sms_opened_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint rr_manual_contact_mode_chk check(data_mode in ('TEST','REAL')),
  constraint rr_manual_contact_wa_chk check(whatsapp_status in ('READY_MANUAL','OPENED_MANUAL','FAILED','DISABLED')),
  constraint rr_manual_contact_sms_chk check(sms_status in ('READY_MANUAL','OPENED_MANUAL','FAILED','DISABLED')),
  constraint rr_manual_contact_one_number_uq unique(source_table,source_id,alert_code,data_mode,recipient_mobile)
);

alter table public.rr_manual_contact_queue_v797_6 enable row level security;
revoke all on public.rr_manual_contact_queue_v797_6 from anon;
revoke insert,update,delete on public.rr_manual_contact_queue_v797_6 from authenticated;
grant select on public.rr_manual_contact_queue_v797_6 to authenticated;

create or replace function public.rr_rate_alert_recipients_v797_5(p_department_code text)
returns table(worker_id text,auth_user_id uuid,worker_name text,leadership_role text,mobile text)
language plpgsql stable security definer set search_path=public as $$
declare v_sql text;
begin
  if to_regclass('public.rr_worker_leadership_board_v777_4') is null then return; end if;
  v_sql := $q$
    select distinct
      to_jsonb(l)->>'worker_id',
      public.rr_try_uuid_v797_5(coalesce(to_jsonb(w)->>'auth_user_id',to_jsonb(w)->>'linked_auth_user_id',to_jsonb(p)->>'auth_user_id',to_jsonb(i)->>'linked_auth_user_id')),
      coalesce(to_jsonb(l)->>'worker_name',to_jsonb(w)->>'worker_name',to_jsonb(i)->>'worker_name',to_jsonb(p)->>'display_name','Management'),
      upper(coalesce(to_jsonb(l)->>'leadership_role','MANAGEMENT')),
      public.rr_normalize_mobile_v797_5(coalesce(to_jsonb(w)->>'mobile',to_jsonb(w)->>'whatsapp_no',to_jsonb(w)->>'phone',to_jsonb(w)->>'mobile_no',to_jsonb(p)->>'mobile',to_jsonb(i)->>'mobile',to_jsonb(i)->>'linked_login_mobile'))
    from public.rr_worker_leadership_board_v777_4 l
    left join public.rr_worker_directory_unified_v1 w on to_jsonb(w)->>'worker_id'=to_jsonb(l)->>'worker_id'
    left join public.rr_user_profiles p on to_jsonb(p)->>'worker_id'=to_jsonb(l)->>'worker_id' or lower(coalesce(to_jsonb(p)->>'display_name',''))=lower(coalesce(to_jsonb(l)->>'worker_name',''))
    left join public.rr_worker_identity_board_v770 i on to_jsonb(i)->>'worker_id'=to_jsonb(l)->>'worker_id'
    where upper(coalesce(to_jsonb(l)->>'leadership_status','ACTIVE'))='ACTIVE'
      and upper(coalesce(to_jsonb(i)->>'is_active','true')) in ('TRUE','T','1','YES')
      and upper(coalesce(to_jsonb(i)->>'access_status','ACTIVE'))='ACTIVE'
      and (upper(coalesce(to_jsonb(l)->>'leadership_role',''))='PRODUCTION_MANAGER'
        or (upper(coalesce(to_jsonb(l)->>'leadership_role',''))='DEPARTMENT_HEAD'
          and upper(coalesce(to_jsonb(l)->>'managed_departments','')) like '%'||upper($1)||'%'))
  $q$;
  return query execute v_sql using p_department_code;
end$$;

create or replace function public.rr_queue_manual_rate_contact_v797_6(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare q public.rr_upm_rate_requests_v760%rowtype; x record; v_msg text; v_mode text; v_count int:=0;
begin
  select * into q from public.rr_upm_rate_requests_v760 where id=p_request_id;
  if not found then raise exception 'Rate request not found.'; end if;
  v_mode:=case when upper(coalesce(q.metadata->>'data_mode','TEST'))='REAL' then 'REAL' else 'TEST' end;
  v_msg:=format('REAL FACTORY %s ALERT: Actual Rate required. Lot %s, Department %s. First Submit blocked hai. Kripya Actual Rate fill/approve karein.',v_mode,q.lot_no,q.department_code);

  for x in
    select mobile,
      jsonb_agg(distinct jsonb_build_object('worker_id',worker_id,'name',worker_name,'role',leadership_role)) as people
    from public.rr_rate_alert_recipients_v797_5(q.department_code)
    where mobile is not null group by mobile
  loop
    insert into public.rr_manual_contact_queue_v797_6(source_table,source_id,alert_code,data_mode,recipient_mobile,intended_recipients,message_text,whatsapp_url,sms_url,metadata)
    values('rr_upm_rate_requests_v760',q.id::text,'ACTUAL_RATE_REQUIRED',v_mode,x.mobile,x.people,v_msg,
      'https://wa.me/'||x.mobile||'?text='||replace(replace(replace(replace(replace(v_msg,'%','%25'),' ','%20'),E'\n','%0A'),'#','%23'),'&','%26'),
      'sms:+'||x.mobile||'?body='||replace(replace(replace(replace(replace(v_msg,'%','%25'),' ','%20'),E'\n','%0A'),'#','%23'),'&','%26'),
      jsonb_build_object('request_token',q.request_token,'request_status',q.request_status,'external_sender_configured',false))
    on conflict(source_table,source_id,alert_code,data_mode,recipient_mobile) do update set
      intended_recipients=excluded.intended_recipients,message_text=excluded.message_text,
      whatsapp_url=excluded.whatsapp_url,sms_url=excluded.sms_url,updated_at=now(),metadata=excluded.metadata;
    v_count:=v_count+1;
  end loop;
  return jsonb_build_object('ok',true,'request_id',q.id,'unique_mobile_count',v_count,'manual_send_required',true);
end$$;

create or replace function public.rr_route_actual_rate_alert_v797_5(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare q public.rr_upm_rate_requests_v760%rowtype; r record; v_count int:=0; v_msg text; v_contact jsonb;
begin
  select * into q from public.rr_upm_rate_requests_v760 where id=p_request_id;
  if not found then raise exception 'Rate request not found.'; end if;
  v_msg:=format('Actual Rate required: Lot %s · Department %s. First Submit blocked hai. कृपया Actual Rate fill/approve करें.',q.lot_no,q.department_code);
  for r in select * from public.rr_rate_alert_recipients_v797_5(q.department_code) loop
    insert into public.rr_global_alert_inbox_v797_5(source_table,source_id,alert_code,recipient_worker_id,recipient_auth_id,recipient_name,recipient_role,recipient_mobile,title,message_text,canonical_lot_id,lot_no,department_code,data_mode,whatsapp_status,metadata)
    values('rr_upm_rate_requests_v760',q.id::text,'ACTUAL_RATE_REQUIRED',r.worker_id,r.auth_user_id,r.worker_name,r.leadership_role,r.mobile,'Actual Rate Approval Required',v_msg,q.canonical_lot_id,q.lot_no,q.department_code,upper(coalesce(q.metadata->>'data_mode','TEST')),case when r.mobile is null then 'NOT_CONFIGURED' else 'READY' end,jsonb_build_object('request_token',q.request_token,'request_status',q.request_status,'manual_whatsapp',true,'manual_sms',true))
    on conflict(source_table,source_id,alert_code,recipient_worker_id) do update set recipient_auth_id=excluded.recipient_auth_id,recipient_mobile=excluded.recipient_mobile,message_text=excluded.message_text,whatsapp_status=excluded.whatsapp_status,delivery_status='IN_APP_READY',is_read=false,read_at=null,updated_at=now(),metadata=excluded.metadata;
    v_count:=v_count+1;
  end loop;
  v_contact:=public.rr_queue_manual_rate_contact_v797_6(q.id);
  update public.rr_upm_rate_requests_v760 set metadata=metadata||jsonb_build_object('alert_engine_version','V797.6','alert_recipient_count',v_count,'manual_contact',v_contact,'alert_queued_at',now(),'external_sender_configured',false) where id=q.id;
  return jsonb_build_object('ok',true,'request_id',q.id,'recipient_count',v_count,'in_app_queued',v_count,'manual_contact',v_contact,'external_sender_configured',false);
end$$;

create or replace function public.rr_manual_rate_contact_payload_v797_6(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v jsonb;
begin
  perform public.rr_queue_manual_rate_contact_v797_6(p_request_id);
  select coalesce(jsonb_agg(jsonb_build_object('queue_id',id,'mobile',recipient_mobile,'recipients',intended_recipients,'message_text',message_text,'whatsapp_url',whatsapp_url,'sms_url',sms_url,'whatsapp_status',whatsapp_status,'sms_status',sms_status) order by created_at),'[]'::jsonb)
  into v from public.rr_manual_contact_queue_v797_6 where source_table='rr_upm_rate_requests_v760' and source_id=p_request_id::text and alert_code='ACTUAL_RATE_REQUIRED';
  return jsonb_build_object('ok',true,'request_id',p_request_id,'contacts',v,'manual_send_required',true,'external_sender_configured',false);
end$$;

create or replace function public.rr_mark_manual_contact_opened_v797_6(p_queue_id uuid,p_channel text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_channel text:=upper(trim(coalesce(p_channel,'')));
begin
  if v_channel not in ('WHATSAPP','SMS') then raise exception 'Channel must be WHATSAPP or SMS.'; end if;
  update public.rr_manual_contact_queue_v797_6 set
    whatsapp_status=case when v_channel='WHATSAPP' then 'OPENED_MANUAL' else whatsapp_status end,
    whatsapp_opened_at=case when v_channel='WHATSAPP' then now() else whatsapp_opened_at end,
    sms_status=case when v_channel='SMS' then 'OPENED_MANUAL' else sms_status end,
    sms_opened_at=case when v_channel='SMS' then now() else sms_opened_at end,updated_at=now()
  where id=p_queue_id;
  if not found then raise exception 'Manual contact queue row not found.'; end if;
  return jsonb_build_object('ok',true,'queue_id',p_queue_id,'channel',v_channel,'status','OPENED_MANUAL','delivered',false);
end$$;

grant execute on function public.rr_manual_rate_contact_payload_v797_6(uuid) to authenticated;
grant execute on function public.rr_mark_manual_contact_opened_v797_6(uuid,text) to authenticated;

do $$ declare q record; begin
  for q in select id from public.rr_upm_rate_requests_v760 where request_status in ('PENDING','OPENED','RATE_FILLED') loop
    perform public.rr_route_actual_rate_alert_v797_5(q.id);
  end loop;
end$$;

comment on table public.rr_manual_contact_queue_v797_6 is 'Manual WhatsApp/SMS launch queue. OPENED_MANUAL never means delivered.';
commit;

select jsonb_build_object('result','OK','version','V797.6','common_in_app_alert',true,'manual_whatsapp',true,'manual_sms',true,'shared_number_dedup',true,'submit_gate_unchanged',true,'external_sender_configured',false,'next','RUN V797.6 VERIFY SQL') as real_factory_v797_6_main_result;
