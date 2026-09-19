-- TEST71 V324: Department Group is a presentation mirror of canonical Submit requests.
begin;

create or replace function public.rr_real_chat_department_submit_mirror_v324(p_department_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $function$
declare v_department text:=public.rr_upm_core_department_v9077(p_department_code);
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  return (
    select jsonb_build_object(
      'version','V324_CANONICAL_DEPARTMENT_SUBMIT_MIRROR',
      'department_code',v_department,
      'cards',coalesce(jsonb_agg(jsonb_build_object(
        'event_key','UPM_SUBMIT_REQUEST:'||q.id::text||':'||a.id::text,
        'canonical_lot_id',a.canonical_lot_id,
        'lot_no',a.lot_no,
        'department_code',public.rr_upm_core_department_v9077(a.department_code),
        'assignment_id',a.id,
        'worker_id',a.worker_id,
        'worker_name',a.worker_name_snapshot,
        'colour_code',a.colour_code,
        'qty',greatest(coalesce(a.inbound_qty,0),coalesce(a.assigned_qty,0)),
        'receipt_status',r.status,
        'assignment_status',a.status,
        'resolved_work_state','CLOSE',
        'source_status','CLOSE',
        'submit_request_id',q.id,
        'submit_status',q.status,
        'message','काम जमा किया · '||coalesce(q.selected_receiver_name,'Receiver')||' को count pending',
        'actions','[]'::jsonb
      ) order by q.created_at desc,a.lot_no,a.colour_code),'[]'::jsonb)
    )
    from public.rr_upm_submit_requests_v794 q
    cross join lateral unnest(q.assignment_ids) aid
    join public.rr_upm_work_assignments_v8 a on a.id=aid
    left join public.rr_upm_assignment_receipts_v9112 r on r.assignment_id=a.id
    where public.rr_upm_core_department_v9077(q.department_code)=v_department
      and upper(q.status) in ('WAITING_LM','ESCALATED','LM_ACCEPTED','LM_COUNTED','COMPLETED')
  );
end
$function$;

revoke all on function public.rr_real_chat_department_submit_mirror_v324(text) from public;
grant execute on function public.rr_real_chat_department_submit_mirror_v324(text) to authenticated;

comment on function public.rr_real_chat_department_submit_mirror_v324(text) is
'TEST71 V324: read-only Department Group mirror of canonical V794 worker Submit handovers; no workflow mutation authority.';

commit;
