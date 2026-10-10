begin;select set_config('request.jwt.claim.sub','893c58dd-420b-4dfa-aff7-844e20e634c5',true);
do $audit$ declare r record;ctx jsonb;home jsonb;outj jsonb:='[]';allowed boolean;error_text text;report_rows int;begin
for r in select worker_id,worker_name from rr_worker_directory_compat_v264 where is_active and lower(worker_name) in('imamul','ali','nasim','shailender','lukman') loop
ctx:=rr_test_set_on_behalf_context_v176(r.worker_id);allowed:=rr_acct_can_view_v805();error_text:=null;
begin home:=rr_accounts_real_chat_home_v500('OPEN','TEST');exception when others then error_text:=sqlerrm;end;
select count(*) into report_rows from rr_trial_balance_v806('2026-01-01','2026-10-10','TEST');
outj:=outj||jsonb_build_array(jsonb_build_object('person',r.worker_name,'effective_role',rr_upm_effective_identity_v200()->>'resolved_role','accounts_home_allowed',error_text is null,'accounts_predicate',allowed,'denial',error_text,'trial_balance_rows',report_rows));
end loop;perform set_config('audit.role.matrix',outj::text,true);end $audit$;
select current_setting('audit.role.matrix')::jsonb result;rollback;
