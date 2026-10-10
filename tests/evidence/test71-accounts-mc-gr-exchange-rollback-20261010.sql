begin;select set_config('request.jwt.claim.sub','893c58dd-420b-4dfa-aff7-844e20e634c5',true);
do $audit$ declare fabric uuid;j jsonb;gr jsonb;ex jsonb;pid uuid;gid uuid;gid2 uuid;outj jsonb:='{}';ref text:='MC-AUDIT-'||gen_random_uuid()::text;n int;begin
select id into fabric from rr_mc1_fabrics where is_active and upper(fabric_name) like 'TEST E2E%' order by created_at limit 1;
j:=rr_post_mc_fabric_purchase_v3(fabric,null,'TEST SUPPLIER E2E',ref,1,100,current_date,'Rollback only');pid:=(j->>'purchase_id')::uuid;
gr:=rr_post_mc_gr_v1(pid,'PARTIAL',0.4,current_date,'Rollback return','Audit',true);gid:=(gr->'gr'->>'id')::uuid;
ex:=rr_post_mc_exchange_v1(gid,0.2,100,ref||'-EX',current_date,'Rollback exchange');
ex:=rr_post_mc_exchange_v1(gid,0.2,100,ref||'-EX',current_date,'Same request retry');
select count(*) into n from rr_product_exchange_entries where gr_id=gid and challan_bill_no=upper(ref||'-EX');
outj:=outj||jsonb_build_object('partial_gr_exchange','PASS','same_exchange_reference_rows',n,'exchange_status',ex->>'gr_status');
gr:=rr_post_mc_gr_v1(pid,'PARTIAL',0.1,current_date,'Closed return','Audit',false);gid2:=(gr->'gr'->>'id')::uuid;
begin ex:=rr_post_mc_exchange_v1(gid2,0.1,100,ref||'-CLOSED',current_date,'Closed exchange test');outj:=outj||jsonb_build_object('closed_without_exchange_accepts_exchange',true);exception when others then outj:=outj||jsonb_build_object('closed_without_exchange_accepts_exchange',false,'denial',sqlerrm);end;
select count(*) into n from rr_account_transactions_v805 where source_record_id=pid::text;
outj:=outj||jsonb_build_object('purchase_accounts_transactions',n,'source_mode_tag',rr_source_data_mode_get_v806('MATCHING_CLOTH_PURCHASE',pid::text));
perform set_config('audit.mc.gr',outj::text,true);end $audit$;
select current_setting('audit.mc.gr')::jsonb result;rollback;
