begin;
select set_config('request.jwt.claim.sub','893c58dd-420b-4dfa-aff7-844e20e634c5',true);
create temporary table future_test(label text,result boolean) on commit drop;
do $audit$ declare fn text; rejected boolean; msg text;begin
foreach fn in array array['rr_attendance_save_v778','rr_recalculate_attendance_day_v778_2','rr_calculate_attendance_day_v778_2'] loop
rejected:=false;
begin
if fn='rr_attendance_save_v778' then perform public.rr_attendance_save_v778('038f2ef4-ca5d-4ed0-a3da-264e2d727ac4',(now() at time zone 'Asia/Kolkata')::date+1,null,null,'AUTO',false,'MANUAL',null,'Rollback future guard','TEST');
else execute format('select public.%I($1,$2,$3)',fn) using '038f2ef4-ca5d-4ed0-a3da-264e2d727ac4'::uuid,(now() at time zone 'Asia/Kolkata')::date+1,'TEST';end if;
exception when others then get stacked diagnostics msg=message_text; rejected:=msg='Future attendance cannot be marked or calculated.';
end;
if not rejected then raise exception 'Future guard failed: %',fn;end if;
insert into future_test values(fn,rejected);
end loop;end $audit$;
select * from future_test;
rollback;
