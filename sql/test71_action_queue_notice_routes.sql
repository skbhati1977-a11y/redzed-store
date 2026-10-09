CREATE OR REPLACE FUNCTION rr_chat_notifications_test71.current_state(p_assignment uuid, p_request uuid, p_department text, p_default text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a record;r record;q record;
begin
 if p_request is not null then
  select * into q from public.rr_upm_submit_requests_v794 where id=p_request;
  if not found or upper(q.status) in ('CANCELLED','CANCELED','REJECTED','VOID') then return null;end if;
  if public.rr_real_chat_canonical_department_v83(q.department_code)=p_department and public.rr_real_chat_canonical_department_v83(coalesce(q.target_department_code,'FABRICATION'))<>p_department then return 'CLOSE';end if;
  return case when upper(q.status)='COMPLETED' then 'CLOSE' else 'WORKING' end;
 elsif p_assignment is not null then
  select * into a from public.rr_upm_work_assignments_v8 where id=p_assignment;
  if not found or upper(a.status) in ('CANCELLED','CANCELED','VOID') then return null;end if;
  if upper(a.status) in ('COMPLETED','CLOSED') or exists(select 1 from public.rr_upm_submit_requests_v794 x where p_assignment=any(x.assignment_ids) and upper(x.status) not in ('CANCELLED','CANCELED','REJECTED','VOID')) then return 'CLOSE';end if;
  select status into r from public.rr_upm_assignment_receipts_v9112 where assignment_id=p_assignment;
  return 'WORKING';
 end if;
 return p_default;
end $function$
;
REVOKE ALL ON FUNCTION rr_chat_notifications_test71.current_state(uuid,uuid,text,text) FROM PUBLIC,anon,authenticated;

