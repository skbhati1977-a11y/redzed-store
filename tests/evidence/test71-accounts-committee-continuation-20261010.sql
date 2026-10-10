begin;
select set_config('request.jwt.claim.sub','893c58dd-420b-4dfa-aff7-844e20e634c5',true);
create temp table audit_result(label text,result jsonb);
do $$ declare r jsonb;r2 jsonb;p uuid;p2 uuid;a jsonb;tx uuid;begin
r:=public.rr_committee_payment_post_v824('3b32ab0d-4e98-4c23-9e7b-7ee62a6036ff',1,1,'CASH','AUDIT-REPEAT',null,current_date,'Rollback audit');
r2:=public.rr_committee_payment_post_v824('3b32ab0d-4e98-4c23-9e7b-7ee62a6036ff',1,1,'CASH','AUDIT-REPEAT',null,current_date,'Rollback audit');
p:=(r->>'payment_id')::uuid;p2:=(r2->>'payment_id')::uuid;
insert into audit_result values('duplicate_reference',jsonb_build_object('two_payments',p<>p2));
a:=public.rr_committee_payment_accounts_post_v825(p);tx:=(a->>'transaction_id')::uuid;
insert into audit_result values('mirror_retry',public.rr_committee_payment_accounts_post_v825(p));
perform public.rr_committee_payment_reverse_v824(p,'AUDIT rollback reversal');
insert into audit_result select 'reversal',jsonb_build_object('payment_status',(select status from public.rr_committee_payments_v824 where id=p),'accounts_status',(select status from public.rr_account_transactions_v805 where id=tx));
end $$;
select * from audit_result;
rollback;
