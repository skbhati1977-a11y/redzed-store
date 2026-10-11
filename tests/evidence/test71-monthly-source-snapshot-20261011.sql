begin;
select set_config('request.jwt.claim.sub','893c58dd-420b-4dfa-aff7-844e20e634c5',true);
create temporary table payroll_coverage_result(label text,result jsonb) on commit drop;
do $test$
declare iid uuid;replacement uuid; w uuid:='038f2ef4-ca5d-4ed0-a3da-264e2d727ac4';d date;r jsonb;p public.rr_worker_payroll_profile_v777_2%rowtype;blocked boolean:=false;pay public.rr_monthly_payroll_v779_1%rowtype;
begin
select * into p from public.rr_active_payroll_profile_v778_2(w,'2026-09-30','TEST');
if p.profile_id is null then raise exception 'Missing September fixture';end if;
perform public.rr_attendance_save_v778(w,'2026-09-15','2026-09-15 10:00+05:30','2026-09-15 20:00+05:30','AUTO',false,'MANUAL',null,'Coverage rollback','TEST');
begin perform public.rr_generate_worker_monthly_payroll_v779_1(w,'2026-09-01','TEST','Coverage rollback');
exception when others then if sqlerrm not like '%Attendance incomplete%' then raise;end if;blocked:=true;end;
if not blocked then raise exception 'One-day payroll unexpectedly generated';end if;
insert into payroll_coverage_result values('one_day_full_salary_blocked','true');
blocked:=false;
begin perform * from public.rr_salary_monthly_earned_v782(w,'2026-09-30','TEST');exception when others then if sqlerrm not like '%Attendance incomplete%' then raise;end if;blocked:=true;end;
if not blocked then raise exception 'Payment board used unresolved attendance';end if;
insert into payroll_coverage_result values('unresolved_payment_board_blocked','true');
for d in select generate_series('2026-09-01'::date,'2026-09-30'::date,interval '1 day')::date loop
perform public.rr_attendance_save_v778(w,d,(d+time '10:00') at time zone 'Asia/Kolkata',(d+time '20:00') at time zone 'Asia/Kolkata','AUTO',false,'MANUAL',null,'Coverage rollback','TEST');
end loop;
perform public.rr_attendance_save_v778(w,'2026-09-07',null,null,'AUTO',false,'MANUAL',null,'Paid Monday rollback','TEST');
if not exists(select 1 from public.rr_attendance_day_v777_2 where worker_id=w and attendance_date='2026-09-07' and data_mode='TEST' and approval_status='APPROVED' and net_deduction_minutes=0 and net_working_minutes=600) then raise exception 'Paid Monday not mapped';end if;
perform public.rr_attendance_save_v778(w,'2026-09-15','2026-09-15 10:00+05:30','2026-09-15 14:00+05:30','HALF_DAY',false,'MANUAL',null,'Actual hours rollback','TEST');
if not exists(select 1 from public.rr_attendance_day_v777_2 where worker_id=w and attendance_date='2026-09-15' and data_mode='TEST' and approval_status='APPROVED' and net_deduction_minutes=360 and net_working_minutes=240) then raise exception 'Half day not using actual punch hours';end if;
insert into payroll_coverage_result values('paid_monday_actual_half_day',jsonb_build_object('paid_monday_minutes',600,'half_day_actual_minutes',240,'half_day_deduction_minutes',360));
if (select earned_to_cutoff from public.rr_salary_monthly_earned_v782(w,'2026-09-30','TEST')) IS DISTINCT FROM round(p.monthly_salary-(public.rr_calculate_monthly_salary_v779_1(p.monthly_salary,360,0,0,0)->>'deduction_amount')::numeric,2) then raise exception 'Payment board ignored actual half day';end if;
insert into payroll_coverage_result values('payment_board_actual_half_day','true');

perform public.rr_attendance_save_v778(w,'2026-09-15','2026-09-15 10:00+05:30','2026-09-15 20:00+05:30','AUTO',false,'MANUAL',null,'Coverage rollback','TEST');
r:=public.rr_generate_worker_monthly_payroll_v779_1(w,'2026-09-01','TEST','Coverage rollback');
select * into pay from public.rr_monthly_payroll_v779_1 where payroll_id=(r->>'payroll_id')::uuid;
if pay.monthly_salary_amount<>p.monthly_salary or pay.scheduled_minutes_snapshot<>18000 then raise exception 'Full coverage salary incorrect';end if;
if (select earned_to_cutoff from public.rr_salary_monthly_earned_v782(w,'2026-09-30','TEST')) IS DISTINCT FROM pay.monthly_salary_amount+pay.net_extra_work_amount then raise exception 'Payment board differs from full month';end if;
insert into payroll_coverage_result values('canonical_payment_board_matches_full_month','true');

insert into public.rr_payroll_incentives_v779_1(worker_id,payroll_month,incentive_type,incentive_amount,incentive_status,data_mode,description,approved_by,approved_at)
values(w,'2026-09-01','MANUAL_APPROVED',50,'APPROVED','TEST','Rollback source snapshot',auth.uid(),now()) returning incentive_id into iid;
blocked:=false;
begin perform public.rr_post_monthly_payroll_v779_2(pay.payroll_id,'Rollback stale draft');exception when others then if sqlerrm not like '%sources changed%' then raise;end if;blocked:=true;end;
if not blocked then raise exception 'Stale draft posted';end if;
insert into payroll_coverage_result values('changed_sources_block_posting','true');
r:=public.rr_generate_worker_monthly_payroll_safe_v779_5(w,'2026-09-01','TEST','Source refresh rollback');
select * into pay from public.rr_monthly_payroll_v779_1 where payroll_id=(r->>'payroll_id')::uuid;
perform public.rr_post_monthly_payroll_v779_2(pay.payroll_id,'Rollback snapshot posting');
update public.rr_payroll_incentives_v779_1 set incentive_amount=60 where incentive_id=iid;
blocked:=false;
begin perform public.rr_finalize_monthly_payroll_v779_2(pay.payroll_id,'Rollback stale final');exception when others then if sqlerrm not like '%sources changed%' then raise;end if;blocked:=true;end;
if not blocked then raise exception 'Stale source finalized';end if;
insert into payroll_coverage_result values('amount_drift_blocks_finalization','true');
update public.rr_payroll_incentives_v779_1 set incentive_amount=50,incentive_status='REVERSED' where incentive_id=iid;
insert into public.rr_payroll_incentives_v779_1(worker_id,payroll_month,incentive_type,incentive_amount,incentive_status,data_mode,description)
values(w,'2026-09-01','MANUAL_APPROVED',50,'APPROVED','TEST','Rollback replacement') returning incentive_id into replacement;
blocked:=false;
begin perform public.rr_finalize_monthly_payroll_v779_2(pay.payroll_id,'Rollback identity drift');exception when others then if sqlerrm not like '%sources changed%' then raise;end if;blocked:=true;end;
if not blocked then raise exception 'Equal amount source swap finalized';end if;
insert into payroll_coverage_result values('equal_amount_identity_swap_blocked','true');
update public.rr_payroll_incentives_v779_1 set incentive_status='REVERSED' where incentive_id=replacement;
update public.rr_payroll_incentives_v779_1 set incentive_status='APPROVED' where incentive_id=iid;
r:=public.rr_finalize_monthly_payroll_v779_2(pay.payroll_id,'Exact sources final rollback');
if r->>'payroll_status'<>'FINAL' or not exists(select 1 from public.rr_payroll_source_applications_v779_1 where payroll_id=pay.payroll_id and source_id=iid and applied_amount=50 and reversed_at is null) then raise exception 'Exact source finalization failed';end if;
insert into payroll_coverage_result values('super_admin_exact_sources_finalize','true');
blocked:=false;
begin perform public.rr_finalize_monthly_payroll_v779_2(pay.payroll_id,'Retry final rollback');exception when others then blocked:=true;end;
if not blocked or (select count(*) from public.rr_payroll_source_applications_v779_1 where payroll_id=pay.payroll_id and source_id=iid and reversed_at is null)<>1 then raise exception 'Source applied twice';end if;
insert into payroll_coverage_result values('duplicate_finalization_no_second_application','true');
end;$test$;
select * from payroll_coverage_result;
rollback;