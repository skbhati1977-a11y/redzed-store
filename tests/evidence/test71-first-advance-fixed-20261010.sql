begin;
select set_config('request.jwt.claim.sub','af915a18-3823-48df-b039-1e4c7a88479b',true);
create temporary table first_advance_result(label text,result jsonb) on commit drop;
do $audit$ declare w uuid;p jsonb;r jsonb;r2 jsonb;k uuid:=gen_random_uuid();b bigint;a bigint;pay jsonb;begin
select x.worker_id into w from public.rr_worker_payroll_board_v777_3 x where x.data_mode='TEST' and x.payroll_profile_status='ACTIVE' and x.worker_category='SALARIED' and x.effective_from<=(now() at time zone 'Asia/Kolkata')::date and coalesce(x.effective_to,'9999-12-31')>=(now() at time zone 'Asia/Kolkata')::date and not exists(select 1 from public.rr_worker_advance_balance_v785 v where v.worker_id=x.worker_id and v.data_mode='TEST' and abs(v.total_advance_balance)>0.005) limit 1;
if w is null then raise exception 'Missing configured zero-balance rollback fixture';end if;
p:=public.rr_advance_payment_preview_v785('TEST','SALARIED',array[w],jsonb_build_array(jsonb_build_object('worker_id',w,'amount_paid',1)));
if (p->>'selected_worker_count')::integer<>1 or (p->>'new_advance_payment_total')::numeric<>1 then raise exception 'First advance not selected';end if;
insert into first_advance_result values('configured_zero_balance_first_issue_preview',jsonb_build_object('selected',1,'amount',1));
pay:=jsonb_build_object('p_data_mode','TEST','p_payroll_category_filter','SALARIED','p_worker_ids',jsonb_build_array(w),'p_worker_amounts',jsonb_build_array(jsonb_build_object('worker_id',w,'amount_paid',1)),'p_payment_date',(now() at time zone 'Asia/Kolkata')::date,'p_payment_mode','CASH','p_voucher_no','AUDIT-FIRST-'||k,'p_remarks','Rollback only');
select count(*) into b from public.rr_account_transactions_v805;
r:=public.rr_financial_request_post_test71('rr_advance_payment_post_v785','TEST',k,pay);
r2:=public.rr_financial_request_post_test71('rr_advance_payment_post_v785','TEST',k,pay);
if r->>'batch_id' is distinct from r2->>'batch_id' then raise exception 'Duplicate first advance';end if;
select count(*) into a from public.rr_account_transactions_v805;
insert into first_advance_result values('first_issue_retry',jsonb_build_object('same_batch',true,'accounts_journal_delta',a-b));
end $audit$;
select * from first_advance_result;
rollback;
