-- Run only as a database regression check. Every change is rolled back.
begin;
do $$
declare a public.rr_upm_work_assignments_v8%rowtype; actor uuid; result jsonb; saved public.rr_upm_submit_requests_v794%rowtype;
begin
 select auth_user_id into actor from public.rr_user_profiles where is_active and upper(role_code)='MANAGER' limit 1;
 select x.* into a from public.rr_upm_work_assignments_v8 x
 where x.status='IN_PROGRESS' and x.department_code not in('STITCHING','OVERLOCK','PRESS')
 and exists(select 1 from public.rr_worker_directory_unified_v1 w where w.worker_id=x.worker_id and w.is_active)
 and exists(select 1 from public.rr_upm_assignment_receipts_v9112 r where r.assignment_id=x.id and r.status in('CONFIRMED','CONFIRMED_SHORT'))
 and not exists(select 1 from public.rr_upm_submit_requests_v794 req where x.id=any(req.assignment_ids) and upper(req.status) not in('CANCELLED','REJECTED','VOID'))
 order by (x.department_code='QC') desc,x.assigned_at desc limit 1;
 if actor is null or a.id is null then raise exception 'Delegated Submit fixture missing'; end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 perform set_config('rr_chat_notifications_test71.test_run','on',true);
 result:=public.rr_chat_submit_worker_test71(a.worker_id,a.canonical_lot_id,a.department_code,jsonb_build_array(jsonb_build_object('colour_code',a.colour_code)),'[]',null);
 select * into saved from public.rr_upm_submit_requests_v794 where id=(result->>'request_id')::uuid;
 if saved.worker_id is distinct from a.worker_id or (result->>'actor_user_id')::uuid is distinct from actor or saved.created_by is distinct from actor then raise exception 'Worker ownership or actor identity mismatch'; end if;
 if not exists(select 1 from public.rr_upm_submit_audit_v794 where request_id=saved.id and action_code='TEST71_SUBMIT_ACTOR' and (details->>'actor_user_id')::uuid=actor) then raise exception 'Actual actor audit missing'; end if;
 if not exists(select 1 from rr_chat_notifications_test71.inbox where submit_request_id=saved.id and recipient_worker_id=a.worker_id and actor_user_id=actor) then raise exception 'Assigned worker did not receive the actual actor notice'; end if;
end $$;
rollback;
