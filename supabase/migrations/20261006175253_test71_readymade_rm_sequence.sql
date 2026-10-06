create table public.rr_rm_lot_renumber_test71(old_lot text primary key,new_lot text unique not null,purchase_id uuid not null,changed_at timestamptz not null default now());
alter table public.rr_rm_lot_renumber_test71 enable row level security;
revoke all on public.rr_rm_lot_renumber_test71 from public,anon,authenticated;
create table public.rr_rm_receipt_renumber_archive_test71(purchase_id uuid primary key,original_asset jsonb not null,archived_at timestamptz not null default now());
alter table public.rr_rm_receipt_renumber_archive_test71 enable row level security;
revoke all on public.rr_rm_receipt_renumber_archive_test71 from public,anon,authenticated;
insert into public.rr_rm_lot_renumber_test71(old_lot,new_lot,purchase_id)
select l.lot_no,'RM'||lpad(row_number() over(order by h.created_at,l.created_at,l.lot_no)::text,3,'0'),l.purchase_id from rr_rm_purchase_lines_v849_2c6 l join rr_rm_purchase_header_v849_2c6 h using(purchase_id) where h.data_mode='TEST';
insert into rr_rm_receipt_renumber_archive_test71 select a.purchase_id,to_jsonb(a),now() from rr_rm_receipt_assets_test71 a where a.purchase_id in(select purchase_id from rr_rm_lot_renumber_test71);
do $$ declare m record;t text;before_qty numeric;after_qty numeric;begin
 select sum(available_qty) into before_qty from rr_rm_stock_v849_2c6 where data_mode='TEST';
 for m in select * from rr_rm_lot_renumber_test71 order by new_lot loop
 if exists(select 1 from rr_fg_products_v787 where lot_no=m.new_lot) or exists(select 1 from rr_lots where lot_no=m.new_lot) then raise exception 'Target Lot % is occupied',m.new_lot;end if;
 end loop;
 for m in select * from rr_rm_lot_renumber_test71 order by new_lot loop
 update rr_rm_purchase_lines_v849_2c6 set lot_no=m.new_lot where purchase_id=m.purchase_id and lot_no=m.old_lot;
 update rr_rm_stock_v849_2c6 set lot_no=m.new_lot where data_mode='TEST' and source_purchase_id=m.purchase_id and lot_no=m.old_lot;
 update rr_fg_products_v787 set lot_no=m.new_lot where lot_no=m.old_lot;
 update rr_universal_lot_registry_v849 set lot_no=m.new_lot,normalized_lot_no=m.new_lot where data_mode='TEST' and source_type='TRADED' and lot_no=m.old_lot;
 foreach t in array array['rr_fg_stock_ledger_v787','rr_web_window_lot_profile_v9329','rr_web_window_allocation_v9329','rr_web_window_allocation_events_v9329','rrq_lot_rates_v9300','rrq_rate_ledger_v9300','rr_trade_special_offer_v849','rr_customer_lot_rate_v9517','rr_customer_lot_rate_history_v9517','rr_pi_internal_rrq_v9517','rr_pi_reservation_v9630'] loop
 execute format('update public.%I set lot_no=$1 where lot_no=$2 and data_mode=''TEST''',t) using m.new_lot,m.old_lot;
 end loop;
 foreach t in array array['rr_fg_pi_lines_v787','rr_fg_returns_v787','rr_sales_journey_line_test_v849','rr_sales_return_test_v849'] loop
 execute format('update public.%I set lot_no=$1 where lot_no=$2 and %s=''TRADED''',t,case when t in('rr_fg_pi_lines_v787','rr_fg_returns_v787') then 'stock_type' else 'source_type' end) using m.new_lot,m.old_lot;
 end loop;
 update rr_stream_pnl_test_v849 set lot_no=m.new_lot where lot_no=m.old_lot and stream_code in('TRADING','TRADED','READYMADE');
 -- These Market cards identify the traded product; manufacturing custody records stay untouched.
 foreach t in array array['rr_market_share_lots_v9420','rr_market_requirement_lines_v9420','rr_market_partner_collection_line_v67','rr_market_partner_order_line_v67','rr_market_partner_customer_ci_line_v67','rr_market_partner_batch_pi_extra_line_v67','rr_rm_retired_share_cards_test71'] loop
 execute format('update public.%I set lot_no=$1 where lot_no=$2',t) using m.new_lot,m.old_lot;
 end loop;
 end loop;
 update rr_rm_receipt_assets_test71 a set snapshot=jsonb_set(a.snapshot,'{lines}',(select jsonb_agg(case when mapping.new_lot is null then v else v||jsonb_build_object('lot_no',mapping.new_lot,'previous_lot_no',v->>'lot_no') end order by ord) from jsonb_array_elements(a.snapshot->'lines') with ordinality e(v,ord) left join rr_rm_lot_renumber_test71 mapping on mapping.old_lot=v->>'lot_no' and mapping.purchase_id=a.purchase_id)),files=null where a.purchase_id in(select purchase_id from rr_rm_lot_renumber_test71);
 select sum(available_qty) into after_qty from rr_rm_stock_v849_2c6 where data_mode='TEST';if before_qty is distinct from after_qty then raise exception 'Renumbering changed stock';end if;
end $$;

create table rr_rm_lot_sequence_test71(data_mode text primary key check(data_mode='TEST'),next_number bigint not null check(next_number>0));
alter table rr_rm_lot_sequence_test71 enable row level security;
revoke all on rr_rm_lot_sequence_test71 from public,anon,authenticated;
insert into rr_rm_lot_sequence_test71 select 'TEST',count(*)+1 from rr_rm_lot_renumber_test71;
CREATE OR REPLACE FUNCTION public.rr_rm_purchase_save_test71(p_purchase_id uuid, p_supplier_name text, p_bill_no text, p_purchase_date date, p_lines jsonb, p_post boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pid uuid;res jsonb;h record;x jsonb; lot_key text;next_rm bigint;expected_rm text;
begin
 perform public.rr_rm_assert_operator_test71();
 if nullif(trim(p_supplier_name),'') is null or p_purchase_date is null then raise exception 'Supplier and Bill Date required.';end if;
 if nullif(trim(p_bill_no),'') is null then raise exception 'Supplier Bill No. required.';end if;

 if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines)=0 then raise exception 'At least one garment required.';end if;
 if exists(select 1 from jsonb_array_elements(p_lines) a group by upper(trim(a->>'lot_no')) having count(*)>1) then raise exception 'Each purchase line needs a different Lot No.';end if;

 select next_number into next_rm from rr_rm_lot_sequence_test71 where data_mode='TEST' for update;
 for x in select value from jsonb_array_elements(p_lines) loop
  lot_key:=upper(trim(x->>'lot_no'));
  if not exists(select 1 from rr_rm_purchase_lines_v849_2c6 where purchase_id=p_purchase_id and upper(trim(lot_no))=lot_key) then
   expected_rm:='RM'||lpad(next_rm::text,greatest(3,length(next_rm::text)),'0');
   if lot_key<>expected_rm then raise exception 'Next Readymade Lot is %. Refresh the suggestion before saving.',expected_rm;end if;
   next_rm:=next_rm+1;
  end if;
 end loop;
 update rr_rm_lot_sequence_test71 set next_number=next_rm where data_mode='TEST';

 for lot_key in select upper(trim(value->>'lot_no')) from jsonb_array_elements(p_lines) order by 1 loop
  perform pg_advisory_xact_lock(hashtextextended('READYMADE-LOT:'||lot_key,0));
  if lot_key !~ '^RM[0-9]+$' and not exists(select 1 from rr_rm_purchase_lines_v849_2c6 where purchase_id=p_purchase_id and upper(trim(lot_no))=lot_key) then raise exception 'New Readymade Lot must use RM followed by numbers, for example RM00001.';end if;
  if exists(select 1 from rr_rm_purchase_lines_v849_2c6 l where upper(trim(l.lot_no))=lot_key and l.purchase_id is distinct from p_purchase_id) then raise exception 'Lot % already belongs to another purchase. Choose the next Readymade Lot.',lot_key;end if;
  if (exists(select 1 from rr_fg_products_v787 where upper(trim(lot_no))=lot_key) or exists(select 1 from rr_lots where upper(trim(lot_no))=lot_key)) and not exists(select 1 from rr_rm_purchase_lines_v849_2c6 where purchase_id=p_purchase_id and upper(trim(lot_no))=lot_key) then raise exception 'Lot % already exists. Choose another Readymade Lot.',lot_key;end if;
 end loop;

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
end $function$
;

create or replace function public.rr_rm_lot_hint_test71() returns jsonb language plpgsql security definer set search_path=public as $$
declare n bigint;
begin perform rr_rm_assert_operator_test71();select next_number into n from rr_rm_lot_sequence_test71 where data_mode='TEST';
return jsonb_build_object('previous_lot',case when n>1 then 'RM'||lpad((n-1)::text,greatest(3,length((n-1)::text)),'0') end,'suggested_lot','RM'||lpad(n::text,greatest(3,length(n::text)),'0'));end $$;
revoke all on function rr_rm_lot_hint_test71() from public,anon;
grant execute on function rr_rm_lot_hint_test71() to authenticated;
