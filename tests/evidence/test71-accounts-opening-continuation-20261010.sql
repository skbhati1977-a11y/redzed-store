begin;
select set_config('request.jwt.claim.sub','af915a18-3823-48df-b039-1e4c7a88479b',true);
create temp table opening_audit(result jsonb);
do $$ declare r jsonb;r2 jsonb;b bigint;begin
select count(*) into b from public.rr_account_transactions_v805;
r:=public.rr_material_opening_balance_v664('77c61feb-f81d-4baa-abb9-b0d8d7eed1b7',10,20,'2026-10-01','TEST','AUDIT-OPENING-ROLLBACK');
r2:=public.rr_material_opening_balance_v664('77c61feb-f81d-4baa-abb9-b0d8d7eed1b7',15,30,'2026-10-01','TEST','AUDIT-OPENING-ROLLBACK');
insert into opening_audit values(jsonb_build_object('first',r,'changed_payload_repeat',r2,'saved_qty',(select purchase_qty from public.rr_material_purchases_v805 where source_record_id='AUDIT-OPENING-ROLLBACK'),'general_accounts_delta',(select count(*)-b from public.rr_account_transactions_v805)));
end $$;
select * from opening_audit;
rollback;
