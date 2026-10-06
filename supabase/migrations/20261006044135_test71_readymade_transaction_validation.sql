create or replace function public.rr_rm_purchase_return_test71(p_stock_id uuid,p_qty numeric,p_reason text,p_return_date date default current_date,p_remarks text default null,p_idempotency_key text default null) returns jsonb language plpgsql security definer set search_path=public as $$
declare s record;h record;rid uuid;party uuid;tx jsonb;avail numeric;already numeric;key text:=nullif(trim(p_idempotency_key),'');
begin
 perform public.rr_rm_assert_operator_test71();
 if key is null then raise exception 'Return request reference required.';end if;
 if coalesce(p_qty,0)<=0 or p_qty::text in('NaN','Infinity','-Infinity') or p_qty<>trunc(p_qty) or nullif(trim(p_reason),'') is null then raise exception 'Whole PCS and return reason required.';end if;
 select * into s from public.rr_rm_stock_v849_2c6 where stock_id=p_stock_id;
 if not found or s.data_mode<>'TEST' then raise exception 'TEST Readymade stock required.';end if;
 perform pg_advisory_xact_lock(hashtextextended('RM:'||upper(trim(s.lot_no))||':TEST',0));
 select * into s from public.rr_rm_stock_v849_2c6 where stock_id=p_stock_id for update;
 select id into rid from public.rr_purchase_returns_v806 where source_module='READYMADE' and source_purchase_id=s.stock_id and source_after->>'idempotency_key'=key and data_mode=s.data_mode;
 if found then return jsonb_build_object('ok',true,'return_id',rid,'duplicate_blocked',true);end if;
 select coalesce(sum(qty_delta),0) into avail from public.rr_fg_stock_ledger_v787 where lot_no=s.lot_no and stock_type='TRADED' and data_mode=s.data_mode;
 select coalesce(sum(return_qty),0) into already from public.rr_purchase_returns_v806 where source_module='READYMADE' and source_purchase_id=s.stock_id and status='POSTED' and data_mode=s.data_mode;
 if p_qty>avail or p_qty>s.qty_received-already then raise exception 'Return exceeds available purchased stock.';end if;
 select * into h from public.rr_rm_purchase_header_v849_2c6 where purchase_id=s.source_purchase_id;
 party:=public.rr_supplier_ledger_resolve_v806(h.supplier_name);
 insert into public.rr_purchase_returns_v806(source_module,source_purchase_id,return_qty,rate_snapshot,return_value,supplier_ledger_id,bill_no,return_date,reason,remarks,data_mode,status,source_before,source_after,created_by)
 values('READYMADE',s.stock_id,p_qty,s.purchase_rate,p_qty*s.purchase_rate,party,coalesce(h.bill_no_test71,h.purchase_no),p_return_date,p_reason,p_remarks,s.data_mode,'POSTED',to_jsonb(s),jsonb_build_object('idempotency_key',key,'lot_no',s.lot_no),auth.uid()) returning id into rid;
 tx:=public.rr_accounts_post_purchase_return_v806('READYMADE_RETURN',rid::text,party,p_qty*s.purchase_rate,coalesce(h.bill_no_test71,h.purchase_no),p_return_date,p_reason,s.data_mode);
 update public.rr_purchase_returns_v806 set account_transaction_id=(tx->>'transaction_id')::uuid where id=rid;
 insert into public.rr_fg_stock_ledger_v787(txn_type,ref_type,ref_id,lot_no,stock_type,qty_delta,rate,data_mode,created_by,meta)
 values('READYMADE_PURCHASE_RETURN','PURCHASE_RETURN',rid,s.lot_no,'TRADED',-p_qty::integer,s.purchase_rate,s.data_mode,auth.uid(),jsonb_build_object('purchase_id',h.purchase_id,'reason',p_reason));
 return jsonb_build_object('ok',true,'return_id',rid,'qty',p_qty,'amount',p_qty*s.purchase_rate,'duplicate_blocked',false);
end $$;
create or replace function public.rr_rm_purchase_save_test71(p_purchase_id uuid,p_supplier_name text,p_bill_no text,p_purchase_date date,p_lines jsonb,p_post boolean default false) returns jsonb language plpgsql security definer set search_path=public as $$
declare pid uuid;res jsonb;h record;
begin
 perform public.rr_rm_assert_operator_test71();
 if nullif(trim(p_supplier_name),'') is null or p_purchase_date is null then raise exception 'Supplier and Bill Date required.';end if;
 if nullif(trim(p_bill_no),'') is null then raise exception 'Supplier Bill No. required.';end if;
 if p_purchase_id is null then
 perform pg_advisory_xact_lock(hashtextextended('RM-BILL:'||public.rr_name_normalize_v805(p_supplier_name)||':'||trim(p_bill_no),0));
 select purchase_id into pid from public.rr_rm_purchase_header_v849_2c6 where public.rr_name_normalize_v805(supplier_name)=public.rr_name_normalize_v805(p_supplier_name) and bill_no_test71=trim(p_bill_no) and data_mode='TEST';
 if found then raise exception 'Supplier bill already exists. Open its saved purchase.';end if;
 res:=public.rr_rm_purchase_create_v849_2c6(p_supplier_name,p_purchase_date,null);pid:=(res->>'purchase_id')::uuid;
 else pid:=p_purchase_id;end if;
 select * into h from public.rr_rm_purchase_header_v849_2c6 where purchase_id=pid for update;
 if h.status='POSTED' then return jsonb_build_object('ok',true,'purchase_id',pid,'status','POSTED','duplicate_blocked',true);end if;
 if h.status<>'DRAFT' or h.data_mode<>'TEST' then raise exception 'TEST Readymade draft required.';end if;
 update public.rr_rm_purchase_header_v849_2c6 set supplier_name=trim(p_supplier_name),bill_no_test71=trim(p_bill_no),purchase_date=p_purchase_date where purchase_id=pid;
 res:=public.rr_rm_purchase_replace_lines_v849_2c6(pid,p_lines);
 if p_post then res:=public.rr_rm_purchase_post_v849_2c6(pid);end if;
 return res||jsonb_build_object('purchase_id',pid);
end $$;