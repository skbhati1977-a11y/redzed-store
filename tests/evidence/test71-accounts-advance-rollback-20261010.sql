begin;select set_config('request.jwt.claim.sub','af915a18-3823-48df-b039-1e4c7a88479b',true);
do $audit$ declare worker uuid; fresh uuid;p jsonb;j jsonb;j2 jsonb;n0 int;n1 int;outj jsonb:='{}';ref text:='ADV-AUDIT-'||gen_random_uuid()::text;begin
select worker_id into worker from rr_worker_advance_balance_v785 where data_mode='TEST' and total_advance_balance>0.005 limit 1;
select d.worker_id into fresh from rr_worker_directory_compat_v264 d where d.is_active and not exists(select 1 from rr_worker_advance_balance_v785 a where a.data_mode='TEST' and a.worker_id=d.worker_id and a.total_advance_balance>0.005) limit 1;
p:=rr_advance_payment_preview_v785('TEST','ALL',array[fresh],jsonb_build_array(jsonb_build_object('worker_id',fresh,'amount_paid',1)));
outj:=outj||jsonb_build_object('first_advance_selected_worker_count',p->>'selected_worker_count','first_advance_new_amount',p->>'new_advance_payment_total');
if worker is not null then
select count(*) into n0 from rr_account_transactions_v805;
j:=rr_advance_payment_post_v785('TEST','ALL',array[worker],jsonb_build_array(jsonb_build_object('worker_id',worker,'amount_paid',0.01)),current_date,'CASH',ref,'Rollback only');
begin j2:=rr_advance_payment_post_v785('TEST','ALL',array[worker],jsonb_build_array(jsonb_build_object('worker_id',worker,'amount_paid',0.01)),current_date,'CASH',ref,'Repeat audit');outj:=outj||jsonb_build_object('same_reference_new_batch',j->>'batch_id'<>j2->>'batch_id');exception when others then outj:=outj||jsonb_build_object('same_reference_repeat_denied',sqlerrm);end;
select count(*) into n1 from rr_account_transactions_v805;outj:=outj||jsonb_build_object('advance_posted',j->>'ok','general_accounts_transaction_delta',n1-n0);
end if;perform set_config('audit.advance',outj::text,true);end $audit$;
select current_setting('audit.advance')::jsonb result;rollback;
