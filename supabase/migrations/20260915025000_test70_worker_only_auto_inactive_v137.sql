-- Keep supervisory staff visible: six-day inactivity is an operational-worker rule.
create index if not exists rr_rc_membership_worker_v136
  on public.rr_real_chat_department_membership_v70(worker_id,is_active);
create index if not exists rr_rc_membership_audit_worker_v136
  on public.rr_real_chat_membership_audit_v136(worker_id,created_at desc);
create index if not exists rr_upm_assignment_worker_activity_v136
  on public.rr_upm_work_assignments_v8(worker_id,status,updated_at desc);

create or replace function public.rr_real_chat_auto_inactive_v136()
returns integer language plpgsql security definer set search_path=''
as $function$
declare v_count integer;
begin
  with last_work as (
    select a.worker_id,max(coalesce(a.updated_at,a.completed_at,a.assigned_at)) last_at,
      bool_or(a.status in ('ASSIGNED','IN_PROGRESS')) has_working
    from public.rr_upm_work_assignments_v8 a group by a.worker_id
  ), due_workers as (
    select distinct m.worker_id
    from public.rr_real_chat_department_membership_v70 m
    join public.rr_worker_directory_unified_v1 d on d.worker_id=m.worker_id and coalesce(d.is_active,false)
    left join last_work w on w.worker_id=m.worker_id
    left join public.rr_real_chat_worker_membership_control_v136 c on c.worker_id=m.worker_id
    where m.is_active and not m.manual_lock and not coalesce(c.manual_global_inactive,false)
      and upper(coalesce(d.role_code,'WORKER')) not in
        ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','ACCOUNT','ACCOUNTS','ACCOUNTANT','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD')
      and not coalesce(w.has_working,false)
      and coalesce(w.last_at,m.last_working_at,m.updated_at,m.created_at)<now()-interval '6 days'
  )
  update public.rr_real_chat_department_membership_v70 m set is_active=false,source_rule='AUTO_INACTIVE_6_DAYS',
    inactive_reason='No active work for 6 continuous days',updated_at=now()
  from due_workers d where m.worker_id=d.worker_id and m.is_active and not m.manual_lock;
  get diagnostics v_count=row_count;
  return v_count;
end $function$;
revoke all on function public.rr_real_chat_auto_inactive_v136() from public,anon,authenticated;
