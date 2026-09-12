-- TEST70 V88: Shailender remains ADMIN and is a monthly salaried worker at INR 18,000.
begin;
do $$
declare v_worker uuid; v_profile uuid; v_shift uuid; v_actor uuid; v_old jsonb; v_new jsonb;
begin
 select d.worker_id into strict v_worker from public.rr_worker_directory_unified_v1 d
 where lower(trim(d.worker_name))='shailender' and coalesce(d.is_active,false)
 order by (d.linked_auth_user_id is not null) desc,d.worker_id limit 1;
 select s.shift_id into strict v_shift from public.rr_shift_master_v777_2 s
 where s.shift_code='GENERAL_10_TO_8' and s.is_active order by s.effective_from desc limit 1;
 select p.profile_id,p.configured_by,to_jsonb(p) into strict v_profile,v_actor,v_old
 from public.rr_worker_payroll_profile_v777_2 p
 where p.worker_id=v_worker and p.status='ACTIVE' and p.data_mode='TEST'
 order by p.effective_from desc,p.configured_at desc limit 1;

 update public.rr_worker_payroll_profile_v777_2 set
  worker_category='SALARIED',shift_id=v_shift,monthly_salary=18000,
  attendance_required=true,piece_advance_percent=0,piece_advance_floor=0,
  advance_cycle='MONTHLY_DAY_20',settlement_cycle='MONTHLY',
  salary_advance_day=20,salary_due_day=7,
  configured_at=now(),reason='TEST70: ADMIN + SALARIED, monthly salary INR 18000'
 where profile_id=v_profile returning to_jsonb(rr_worker_payroll_profile_v777_2.*) into v_new;

 update public.rr_worker_accounts_map_v9785 set payroll_category='SALARIED',updated_at=now()
 where worker_id=v_worker;

 insert into public.rr_worker_payroll_profile_events_v777_2
  (worker_id,profile_id,event_type,old_snapshot,new_snapshot,actor_auth_user_id,actor_name,reason)
 values(v_worker,v_profile,'PROFILE_UPDATED',v_old,v_new,v_actor,'System Migration',
  'TEST70: Shailender ADMIN role retained; SALARIED INR 18000 configured');
end $$;
commit;
