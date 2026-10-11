begin;
select set_config('request.jwt.claim.sub','af915a18-3823-48df-b039-1e4c7a88479b',true);
create temporary table mc_accounts_result(label text,result jsonb) on commit drop;
do $test$
declare k uuid:=gen_random_uuid();p jsonb;r jsonb;s jsonb;before_n bigint;before_j bigint;changed boolean:=false;
begin
select count(*) into before_n from public.rr_mc1_purchases;
select count(*) into before_j from public.rr_account_transactions_v805;
p:=jsonb_build_object('p_fabric_id',null,'p_fabric_name','ROLLBACK MC '||k,'p_vendor_name','ROLLBACK MC VENDOR '||k,'p_bill_no','ROLLBACK-MC-'||k,'p_bill_qty',2,'p_bill_value',4,'p_bill_date',current_date,'p_remarks','Rollback only','p_data_mode','TEST','p_supplier_ledger_id',null);
r:=public.rr_financial_request_post_test71('rr_post_mc_purchase_accounts_test71','TEST',k,p);
s:=public.rr_financial_request_post_test71('rr_post_mc_purchase_accounts_test71','TEST',k,p);
if r->>'purchase_id' is distinct from s->>'purchase_id' then raise exception 'Matching retry duplicated purchase';end if;
if (select count(*) from public.rr_mc1_purchases)<>before_n+1 or (select count(*) from public.rr_account_transactions_v805)<>before_j+1 then raise exception 'Expected exactly one purchase and journal';end if;
if public.rr_source_data_mode_get_v806('MATCHING_CLOTH_PURCHASE',r->>'purchase_id') is distinct from 'TEST' then raise exception 'Matching mode tag missing';end if;
if not exists(select 1 from public.rr_account_transactions_v805 where id=(r->>'accounts_transaction_id')::uuid and source_module='MATCHING_CLOTH_PURCHASE' and source_record_id=r->>'purchase_id' and data_mode='TEST') then raise exception 'Atomic source link missing';end if;
begin perform public.rr_financial_request_post_test71('rr_post_mc_purchase_accounts_test71','TEST',k,p||jsonb_build_object('p_bill_qty',3));
exception when others then if sqlerrm not like '%different payload%' then raise;end if;changed:=true;end;
if not changed then raise exception 'Changed matching retry allowed';end if;
if exists(select 1 from public.rr_account_postings_v805 where transaction_id=(r->>'accounts_transaction_id')::uuid group by transaction_id having sum(dr_amount)<>sum(cr_amount)) then raise exception 'Matching journal unbalanced';end if;
insert into mc_accounts_result values('atomic_matching_purchase',jsonb_build_object('one_purchase',true,'one_journal',true,'mode_tag','TEST','changed_retry_denied',true,'balanced',true));
end;$test$;
select * from mc_accounts_result;
rollback;