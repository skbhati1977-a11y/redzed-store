begin;
select set_config('request.jwt.claim.sub','af915a18-3823-48df-b039-1e4c7a88479b',true);
create temp table audit_result(label text,result jsonb);
do $$ declare m public.rr_material_master_v805%rowtype;s uuid;l uuid;c uuid;r jsonb;r2 jsonb;rt jsonb;pid uuid;mode text;paid numeric;tx uuid;begin
select * into m from public.rr_material_master_v805 where id='77c61feb-f81d-4baa-abb9-b0d8d7eed1b7';
select id into s from public.rr_ledgers_v805 where ledger_code='TST-CREDITOR-V818';
select id into l from public.rr_ledgers_v805 where ledger_kind='PURCHASE' and ledger_code is distinct from 'PUR_RETURN' and is_active limit 1;
select id into c from public.rr_ledgers_v805 where ledger_code='CASH_MAIN';
foreach mode in array array['CREDIT','PARTIAL','PAID'] loop
paid:=case mode when 'CREDIT' then 0 when 'PARTIAL' then 10 else 20 end;
r:=public.rr_material_post_purchase_v805_1(s,m.id,l,10,m.purchase_unit,10,m.base_stock_unit,10,m.consumption_unit,2,'AUDIT-MAT-'||mode,current_date,0,mode,paid,c,'TEST');
insert into audit_result values(mode,r);
if mode='CREDIT' then
pid:=(r->>'purchase_id')::uuid;
r2:=public.rr_material_post_purchase_v805_1(s,m.id,l,10,m.purchase_unit,10,m.base_stock_unit,10,m.consumption_unit,2,'AUDIT-MAT-'||mode,current_date,0,mode,paid,c,'TEST');
insert into audit_result values('same_bill_retry',jsonb_build_object('two_purchases',pid<>(r2->>'purchase_id')::uuid));
begin rt:=public.rr_material_purchase_return_v806(pid,2,'AUDIT partial return',current_date,null);
insert into audit_result values('partial_return',rt);
insert into audit_result values('return_reverse',public.rr_material_purchase_return_reverse_v806((rt->>'purchase_return_id')::uuid,'AUDIT rollback reverse')); exception when others then insert into audit_result values('return_failed',jsonb_build_object('error',sqlerrm,'saved_purchase',(select to_jsonb(p) from public.rr_material_purchases_v805 p where p.id=pid)));end;
end if;
end loop;
end $$;
select * from audit_result;
rollback;
