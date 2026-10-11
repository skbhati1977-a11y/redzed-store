begin;
select set_config('request.jwt.claim.sub','893c58dd-420b-4dfa-aff7-844e20e634c5',true);
create temp table audit_result(label text,result jsonb);
do $$
declare w uuid:='038f2ef4-ca5d-4ed0-a3da-264e2d727ac4';r public.rr_attendance_day_v778%rowtype;b bigint;blocked boolean;
begin
select count(*) into b from public.rr_attendance_day_v777_2 where worker_id=w;
r:=public.rr_attendance_save_v778(w,'2026-09-15','2026-09-15 09:00+05:30','2026-09-15 18:00+05:30','AUTO',false,'MANUAL',null,'AUDIT rollback','TEST');
if (select count(*)-b from public.rr_attendance_day_v777_2 where worker_id=w)<>1 then raise exception 'Manual attendance did not create canonical day';end if;
insert into audit_result values('present',jsonb_build_object('status',r.status,'canonical_v777_delta',(select count(*)-b from public.rr_attendance_day_v777_2 where worker_id=w)));
r:=public.rr_attendance_save_v778(w,'2026-09-15','2026-09-15 09:00+05:30',null,'AUTO',false,'CORRECTION',null,'AUDIT incomplete','TEST');
if not exists(select 1 from public.rr_attendance_day_v777_2 where worker_id=w and attendance_date='2026-09-15' and data_mode='TEST' and approval_status='PENDING' and net_deduction_minutes=0 and net_working_minutes=0) then raise exception 'Incomplete attendance leaked deduction or approval';end if;
insert into audit_result values('missing_checkout',jsonb_build_object('status',r.status,'revision',r.revision_no));
blocked:=false;begin perform public.rr_attendance_save_v778(w,'2026-09-15','2026-09-15 09:00+05:30',null,'PRESENT',false,'MANUAL',null,'AUDIT invalid','TEST');exception when others then blocked:=true;end;
insert into audit_result values('present_without_checkout_denied',to_jsonb(blocked));
blocked:=false;begin perform public.rr_attendance_save_v778(w,'2026-09-15','2026-09-15 18:00+05:30','2026-09-15 09:00+05:30','AUTO',false,'MANUAL',null,'AUDIT invalid','TEST');exception when others then blocked:=true;end;
insert into audit_result values('reversed_punch_denied',to_jsonb(blocked));
blocked:=false;begin perform public.rr_attendance_save_v778(w,'2026-08-01',null,null,'AUTO',false,'MANUAL',null,'AUDIT before profile','TEST');exception when others then blocked:=true;end;
insert into audit_result values('before_profile_denied',to_jsonb(blocked));
end $$;
select * from audit_result;
rollback;


begin;
select set_config('request.jwt.claim.sub','893c58dd-420b-4dfa-aff7-844e20e634c5',true);
create temporary table payroll_coverage_result(label text,result jsonb) on commit drop;
do $test$
declare w uuid:='038f2ef4-ca5d-4ed0-a3da-264e2d727ac4';d date;r jsonb;p public.rr_worker_payroll_profile_v777_2%rowtype;blocked boolean:=false;pay public.rr_monthly_payroll_v779_1%rowtype;
begin
select * into p from public.rr_active_payroll_profile_v778_2(w,'2026-09-30','TEST');
if p.profile_id is null then raise exception 'Missing September fixture';end if;
perform public.rr_attendance_save_v778(w,'2026-09-15','2026-09-15 10:00+05:30','2026-09-15 20:00+05:30','AUTO',false,'MANUAL',null,'Coverage rollback','TEST');
begin perform public.rr_generate_worker_monthly_payroll_v779_1(w,'2026-09-01','TEST','Coverage rollback');
exception when others then if sqlerrm not like '%Attendance incomplete%' then raise;end if;blocked:=true;end;
if not blocked then raise exception 'One-day payroll unexpectedly generated';end if;
insert into payroll_coverage_result values('one_day_full_salary_blocked','true');
for d in select generate_series('2026-09-01'::date,'2026-09-30'::date,interval '1 day')::date loop
perform public.rr_attendance_save_v778(w,d,(d+time '10:00') at time zone 'Asia/Kolkata',(d+time '20:00') at time zone 'Asia/Kolkata','AUTO',false,'MANUAL',null,'Coverage rollback','TEST');
end loop;
perform public.rr_attendance_save_v778(w,'2026-09-07',null,null,'AUTO',false,'MANUAL',null,'Paid Monday rollback','TEST');
if not exists(select 1 from public.rr_attendance_day_v777_2 where worker_id=w and attendance_date='2026-09-07' and data_mode='TEST' and approval_status='APPROVED' and net_deduction_minutes=0 and net_working_minutes=600) then raise exception 'Paid Monday not mapped';end if;
perform public.rr_attendance_save_v778(w,'2026-09-15','2026-09-15 10:00+05:30','2026-09-15 14:00+05:30','HALF_DAY',false,'MANUAL',null,'Actual hours rollback','TEST');
if not exists(select 1 from public.rr_attendance_day_v777_2 where worker_id=w and attendance_date='2026-09-15' and data_mode='TEST' and approval_status='APPROVED' and net_deduction_minutes=360 and net_working_minutes=240) then raise exception 'Half day not using actual punch hours';end if;
insert into payroll_coverage_result values('paid_monday_actual_half_day',jsonb_build_object('paid_monday_minutes',600,'half_day_actual_minutes',240,'half_day_deduction_minutes',360));
perform public.rr_attendance_save_v778(w,'2026-09-15','2026-09-15 10:00+05:30','2026-09-15 20:00+05:30','AUTO',false,'MANUAL',null,'Coverage rollback','TEST');
r:=public.rr_generate_worker_monthly_payroll_v779_1(w,'2026-09-01','TEST','Coverage rollback');
select * into pay from public.rr_monthly_payroll_v779_1 where payroll_id=(r->>'payroll_id')::uuid;
if pay.monthly_salary_amount<>p.monthly_salary or pay.scheduled_minutes_snapshot<>18000 then raise exception 'Full coverage salary incorrect';end if;
update public.rr_worker_payroll_profile_v777_2 set effective_from='2026-09-15' where profile_id=p.profile_id;
r:=public.rr_generate_worker_monthly_payroll_v779_1(w,'2026-09-01','TEST','Partial month rollback');
select * into pay from public.rr_monthly_payroll_v779_1 where payroll_id=(r->>'payroll_id')::uuid;
if pay.monthly_salary_amount<>round(p.monthly_salary*16/30.0,2) or pay.scheduled_minutes_snapshot<>9600 then raise exception 'Fixed thirty day partial salary incorrect: % / %',pay.monthly_salary_amount,pay.scheduled_minutes_snapshot;end if;
if pay.per_minute_rate<>round(p.monthly_salary/18000.0,8) then raise exception 'Partial month altered time rate';end if;
insert into payroll_coverage_result values('complete_month_and_partial_30_day',jsonb_build_object('full_month_passed',true,'partial_days',16,'partial_fixed_30_passed',true,'outside_activation_days_excluded',true,'minute_rate_preserved',true));
end;$test$;
select * from payroll_coverage_result;
rollback;