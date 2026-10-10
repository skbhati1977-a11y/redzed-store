begin;select set_config('request.jwt.claim.sub','af915a18-3823-48df-b039-1e4c7a88479b',true);
do $audit$ declare dept text;source text;lot text;j jsonb;outj jsonb:='[]';n int;amount numeric;after_amount numeric;begin
foreach dept in array array['CUTTING','FABRICATION','PRINTING','METAL_ID','STICKER','STITCHING','OVERLOCK','FOLDING','KAJ_BUTTON','TEAK_TANKI','THREAD_CUT','QC','PRESS','PACKING'] loop
source:='AUDIT-'||gen_random_uuid()::text;lot:='AUDIT-LOT-'||source;
perform rr_payroll_alter_reserve_v800(source,'e959bce6-d191-4198-98bc-bb6c1ed27770','Audit worker',lot,lot,dept,null,'C1','L',2,3);
perform rr_payroll_alter_reserve_v800(source,'e959bce6-d191-4198-98bc-bb6c1ed27770','Audit worker',lot,lot,dept,null,'C1','L',2,3);
j:=rr_upm_alter_despatch_final_claim_v800(lot);perform rr_upm_alter_despatch_final_claim_v800(lot);
select count(*),sum(debit_amount) into n,amount from rr_worker_claim_debit_v800 where source_id=source;
if n<>1 or amount<>6 then raise exception 'Alter claim duplicate/value failed %',dept;end if;
begin
perform rr_payroll_alter_reserve_v800(source,'e959bce6-d191-4198-98bc-bb6c1ed27770','Audit worker',lot,lot,dept,null,'C1','L',5,4);
raise exception 'TEST71_INVALID_FINALIZED_MUTATION_ACCEPTED';
exception when others then
 if sqlerrm not like 'Finalized Alter claim is immutable%' then raise;end if;
end;
select reserve_amount into after_amount from rr_payroll_claim_reserve_v800 where source_id=source;
if after_amount<>6 then raise exception 'Finalized amount changed %',dept;end if;
outj:=outj||jsonb_build_array(jsonb_build_object('department',dept,'retry_single_claim',true,'claim_amount',amount,'converted_reserve_preserved_amount',after_amount));
end loop;perform set_config('audit.alter.claims',outj::text,true);end $audit$;
select current_setting('audit.alter.claims')::jsonb result;rollback;

