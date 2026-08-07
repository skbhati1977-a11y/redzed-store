-- REAL FACTORY V797.6
-- READ-ONLY VERIFY SQL
-- Checks the combined in-app alert + manual WhatsApp + manual SMS foundation.
-- This script does not create alerts, queue messages, open apps, or change status.

with
object_check as (
  select
    to_regclass('public.rr_manual_contact_queue_v797_6') is not null as queue_table_ok,
    to_regclass('public.rr_global_alert_inbox_v797_5') is not null as inbox_table_ok,
    to_regclass('public.rr_upm_rate_requests_v760') is not null as rate_request_table_ok,
    to_regprocedure('public.rr_rate_alert_recipients_v797_5(text)') is not null as recipient_resolver_ok,
    to_regprocedure('public.rr_queue_manual_rate_contact_v797_6(uuid)') is not null as queue_function_ok,
    to_regprocedure('public.rr_route_actual_rate_alert_v797_5(uuid)') is not null as route_function_ok,
    to_regprocedure('public.rr_manual_rate_contact_payload_v797_6(uuid)') is not null as payload_function_ok,
    to_regprocedure('public.rr_mark_manual_contact_opened_v797_6(uuid,text)') is not null as opened_function_ok
),
printing_recipients as (
  select worker_id, worker_name, leadership_role, mobile
  from public.rr_rate_alert_recipients_v797_5('PRINTING')
),
recipient_check as (
  select
    count(*) as recipient_rows,
    count(*) filter (where mobile is not null) as mobile_ready_rows,
    count(distinct mobile) filter (where mobile is not null) as unique_mobile_count,
    bool_or(lower(coalesce(worker_name,'')) like '%sanju%') as sanju_resolved,
    bool_or(lower(coalesce(worker_name,'')) like '%nasim%') as nasim_resolved,
    coalesce(jsonb_agg(
      jsonb_build_object(
        'worker_id',worker_id,
        'name',worker_name,
        'role',leadership_role,
        'mobile_ready',mobile is not null,
        'mobile_last4',case when mobile is null then null else right(mobile,4) end
      ) order by worker_name
    ),'[]'::jsonb) as recipients
  from printing_recipients
),
queue_check as (
  select
    count(*) as total_rows,
    count(*) filter (where alert_code='ACTUAL_RATE_REQUIRED') as actual_rate_rows,
    count(*) filter (where whatsapp_status='READY_MANUAL') as whatsapp_ready_rows,
    count(*) filter (where sms_status='READY_MANUAL') as sms_ready_rows,
    count(*) filter (where whatsapp_status='OPENED_MANUAL') as whatsapp_opened_rows,
    count(*) filter (where sms_status='OPENED_MANUAL') as sms_opened_rows,
    count(*) filter (where whatsapp_status not in ('READY_MANUAL','OPENED_MANUAL','FAILED','DISABLED')) as invalid_whatsapp_status_rows,
    count(*) filter (where sms_status not in ('READY_MANUAL','OPENED_MANUAL','FAILED','DISABLED')) as invalid_sms_status_rows,
    count(*) filter (where whatsapp_url not like 'https://wa.me/%') as invalid_whatsapp_url_rows,
    count(*) filter (where sms_url not like 'sms:+%') as invalid_sms_url_rows,
    count(*) filter (where coalesce(metadata->>'external_sender_configured','false') <> 'false') as false_delivery_claim_rows
  from public.rr_manual_contact_queue_v797_6
),
dedup_check as (
  select count(*) as duplicate_key_groups
  from (
    select source_table,source_id,alert_code,data_mode,recipient_mobile
    from public.rr_manual_contact_queue_v797_6
    group by source_table,source_id,alert_code,data_mode,recipient_mobile
    having count(*) > 1
  ) d
),
pending_check as (
  select
    count(*) as open_rate_requests,
    count(*) filter (where exists (
      select 1 from public.rr_global_alert_inbox_v797_5 i
      where i.source_table='rr_upm_rate_requests_v760'
        and i.source_id=r.id::text
        and i.alert_code='ACTUAL_RATE_REQUIRED'
    )) as open_requests_with_in_app_alert,
    count(*) filter (where exists (
      select 1 from public.rr_manual_contact_queue_v797_6 q
      where q.source_table='rr_upm_rate_requests_v760'
        and q.source_id=r.id::text
        and q.alert_code='ACTUAL_RATE_REQUIRED'
    )) as open_requests_with_manual_contact
  from public.rr_upm_rate_requests_v760 r
  where r.request_status in ('PENDING','OPENED','RATE_FILLED')
),
result_check as (
  select
    o.*,
    r.*,
    q.*,
    d.duplicate_key_groups,
    p.*,
    (
      o.queue_table_ok and o.inbox_table_ok and o.rate_request_table_ok
      and o.recipient_resolver_ok and o.queue_function_ok and o.route_function_ok
      and o.payload_function_ok and o.opened_function_ok
      and r.sanju_resolved and r.nasim_resolved
      and r.mobile_ready_rows = r.recipient_rows
      and r.unique_mobile_count = 1
      and q.invalid_whatsapp_status_rows = 0
      and q.invalid_sms_status_rows = 0
      and q.invalid_whatsapp_url_rows = 0
      and q.invalid_sms_url_rows = 0
      and q.false_delivery_claim_rows = 0
      and d.duplicate_key_groups = 0
      and (p.open_rate_requests = 0 or (
        p.open_requests_with_in_app_alert = p.open_rate_requests
        and p.open_requests_with_manual_contact = p.open_rate_requests
      ))
    ) as overall_pass
  from object_check o
  cross join recipient_check r
  cross join queue_check q
  cross join dedup_check d
  cross join pending_check p
)
select jsonb_build_object(
  'result',case when overall_pass then 'PASS' else 'CHECK_REQUIRED' end,
  'version','V797.6',
  'read_only',true,
  'objects',jsonb_build_object(
    'queue_table',queue_table_ok,
    'inbox_table',inbox_table_ok,
    'rate_request_table',rate_request_table_ok,
    'recipient_resolver',recipient_resolver_ok,
    'queue_function',queue_function_ok,
    'route_function',route_function_ok,
    'payload_function',payload_function_ok,
    'opened_function',opened_function_ok
  ),
  'printing_recipient_check',jsonb_build_object(
    'recipient_rows',recipient_rows,
    'mobile_ready_rows',mobile_ready_rows,
    'unique_mobile_count',unique_mobile_count,
    'shared_number_dedup_ready',recipient_rows >= 2 and unique_mobile_count = 1,
    'sanju_resolved',sanju_resolved,
    'nasim_resolved',nasim_resolved,
    'recipients',recipients
  ),
  'manual_contact_queue',jsonb_build_object(
    'total_rows',total_rows,
    'actual_rate_rows',actual_rate_rows,
    'whatsapp_ready_rows',whatsapp_ready_rows,
    'sms_ready_rows',sms_ready_rows,
    'whatsapp_opened_rows',whatsapp_opened_rows,
    'sms_opened_rows',sms_opened_rows,
    'invalid_whatsapp_status_rows',invalid_whatsapp_status_rows,
    'invalid_sms_status_rows',invalid_sms_status_rows,
    'invalid_whatsapp_url_rows',invalid_whatsapp_url_rows,
    'invalid_sms_url_rows',invalid_sms_url_rows,
    'false_delivery_claim_rows',false_delivery_claim_rows,
    'duplicate_key_groups',duplicate_key_groups
  ),
  'pending_rate_requests',jsonb_build_object(
    'open_count',open_rate_requests,
    'with_in_app_alert',open_requests_with_in_app_alert,
    'with_manual_contact',open_requests_with_manual_contact
  ),
  'submit_gate_unchanged',true,
  'external_sender_configured',false,
  'next',case when overall_pass then 'BUILD MATCHING HTML + JS' else 'SEND THIS FULL RESULT FOR CORRECTION' end
) as real_factory_v797_6_verify_result
from result_check;
