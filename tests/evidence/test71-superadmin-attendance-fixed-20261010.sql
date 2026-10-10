begin;
select set_config('request.jwt.claim.sub','893c58dd-420b-4dfa-aff7-844e20e634c5',true);
create temp table audit_result(label text,result jsonb);
do $$
declare w uuid:='038f2ef4-ca5d-4ed0-a3da-264e2d727ac4';r public.rr_attendance_day_v778%rowtype;b bigint;blocked boolean;
begin
select count(*) into b from public.rr_attendance_day_v777_2 where worker_id=w;
r:=public.rr_attendance_save_v778(w,'2026-09-15','2026-09-15 09:00+05:30','2026-09-15 18:00+05:30','AUTO',false,'MANUAL',null,'AUDIT rollback','TEST');
insert into audit_result values('present',jsonb_build_object('status',r.status,'canonical_v777_delta',(select count(*)-b from public.rr_attendance_day_v777_2 where worker_id=w)));
r:=public.rr_attendance_save_v778(w,'2026-09-15','2026-09-15 09:00+05:30',null,'AUTO',false,'CORRECTION',null,'AUDIT incomplete','TEST');
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

