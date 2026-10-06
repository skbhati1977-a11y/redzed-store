begin;
select public.rr_fg_assert_user_v787();
do $$ declare h record;begin
 for h in select * from public.rr_rm_purchase_header_v849_2c6 where data_mode='TEST' and status='POSTED' order by purchase_no loop
 perform public.rr_rm_finish_purchase_test71(h.purchase_id);
 insert into public.rr_rm_purchase_audit_v849_2c6(purchase_id,purchase_no,action_code,details)
 select h.purchase_id,h.purchase_no,'TEST71_WIRING_RECONCILED',jsonb_build_object('stock_and_accounts','CANONICAL','owner_margin',22)
 where not exists(select 1 from public.rr_rm_purchase_audit_v849_2c6 where purchase_id=h.purchase_id and action_code='TEST71_WIRING_RECONCILED');
 end loop;
 update public.rr_rm_stock_v849_2c6 s set sale_ready=false where data_mode='TEST' and not exists(select 1 from public.rrq_lot_rates_v9300 q where q.lot_no=s.lot_no and q.data_mode=s.data_mode and q.dispatch_ready);
end $$;
select h.purchase_no,h.account_transaction_id_test71 is not null as accounts_posted,
 (select count(*) from public.rr_fg_stock_ledger_v787 l join public.rr_rm_stock_v849_2c6 s on s.stock_id=l.ref_id where s.source_purchase_id=h.purchase_id and l.txn_type='READYMADE_PURCHASE_IN') as stock_in_lines
 from public.rr_rm_purchase_header_v849_2c6 h where h.data_mode='TEST' and h.status='POSTED';
commit;
