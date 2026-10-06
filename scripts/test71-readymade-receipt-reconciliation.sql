-- Ready-made receipt quantities use PCS; existing TEST-only Accounts and stock engines.
alter table public.rr_rm_purchase_lines_v849_2c6 add column if not exists bill_qty_test71 numeric;
alter table public.rr_rm_purchase_lines_v849_2c6 add column if not exists receipt_note_transaction_id_test71 uuid references public.rr_account_transactions_v805(id);
alter table public.rr_rm_purchase_lines_v849_2c6 add constraint rr_rm_bill_qty_whole_test71 check (bill_qty_test71 is null or (bill_qty_test71>0 and bill_qty_test71=trunc(bill_qty_test71) and bill_qty_test71::text not in ('NaN','Infinity','-Infinity')));

CREATE OR REPLACE FUNCTION public.rr_rm_purchase_replace_lines_v849_2c6(p_purchase_id uuid, p_lines jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$

declare
    v_header record;

    v_json_line jsonb;

    v_lot_no text;

    v_item_name text;

    v_qty numeric;
    v_bill_qty numeric;

    v_purchase_rate numeric;

    v_markup_mode text;

    v_markup numeric;

    v_image text;

    v_line_count integer:=0;

begin
    perform public.rr_rm_assert_operator_test71();

    select *
    into v_header

    from public.rr_rm_purchase_header_v849_2c6

    where purchase_id=p_purchase_id

    for update;


    if not found then
      raise exception
        'ReadyMade purchase not found.';
    end if;


    if v_header.status<>'DRAFT' then
      raise exception
        'Only DRAFT purchase can be edited.';
    end if;


    if p_lines is null
       or jsonb_typeof(p_lines)<>'array'
    then
      raise exception
        'Lines JSON array required.';
    end if;


    delete from public.rr_rm_purchase_lines_v849_2c6

    where purchase_id=p_purchase_id;


    for v_json_line in

      select value

      from jsonb_array_elements(p_lines)

    loop

      v_lot_no :=
        nullif(
          trim(
            coalesce(
              v_json_line->>'lot_no',
              ''
            )
          ),
          ''
        );


      v_item_name :=
        nullif(
          trim(
            coalesce(
              v_json_line->>'item_name',
              ''
            )
          ),
          ''
        );


      v_qty :=
        nullif(
          v_json_line->>'qty',
          ''
        )::numeric;


      v_purchase_rate :=
        nullif(
          v_json_line->>'purchase_rate',
          ''
        )::numeric;


      v_markup_mode :=
        upper(
          trim(
            coalesce(
              v_json_line->>'markup_mode',
              'DEFAULT_22'
            )
          )
        );


      v_image :=
        nullif(
          trim(
            coalesce(
              v_json_line->>'final_image_url',
              ''
            )
          ),
          ''
        );


      if v_lot_no is null then
        raise exception
          'Lot No required.';
      end if;


      if v_item_name is null then
        raise exception
          'Item Name required for Lot %.',
          v_lot_no;
      end if;


      if coalesce(v_qty,0)<=0 then
        raise exception
          'Positive Qty required for Lot %.',
          v_lot_no;
      end if;


      if coalesce(v_purchase_rate,0)<=0 then
        raise exception
          'Positive Purchase Rate required for Lot %.',
          v_lot_no;
      end if;


      v_bill_qty:=coalesce(nullif(v_json_line->>'bill_qty','')::numeric,v_qty);
      if v_qty::text in ('NaN','Infinity','-Infinity') or v_bill_qty::text in ('NaN','Infinity','-Infinity') or v_purchase_rate::text in ('NaN','Infinity','-Infinity') or v_bill_qty<=0 or v_bill_qty<>trunc(v_bill_qty) then
        raise exception 'Enter positive whole Party Bill PCS and Received PCS with a valid purchase rate.';
      end if;
      v_markup_mode:='DEFAULT_22'; v_markup:=22;
      if v_qty<>trunc(v_qty) then raise exception 'Readymade quantity must be whole PCS.'; end if;

      insert into public.rr_rm_purchase_lines_v849_2c6
      (
        purchase_id,
        lot_no,
        item_name,
        qty,
        bill_qty_test71,
        purchase_rate,
        markup_mode,
        markup_per_pc,
        max_customer_discount_per_pc,
        final_image_url,
        source_type
      )
      values
      (
        p_purchase_id,
        v_lot_no,
        v_item_name,
        v_qty,
        v_bill_qty,
        v_purchase_rate,
        v_markup_mode,
        v_markup,
        10,
        v_image,
        'TRADED'
      );


      v_line_count :=
        v_line_count+1;

    end loop;


    update public.rr_rm_purchase_header_v849_2c6 h

    set
      total_qty=
        (
          select coalesce(
                   sum(pl.qty),
                   0
                 )

          from public.rr_rm_purchase_lines_v849_2c6 pl

          where pl.purchase_id=p_purchase_id
        ),

      total_purchase_amount=
        (
          select coalesce(
                   sum(round(coalesce(pl.bill_qty_test71,pl.qty)*pl.purchase_rate,2)),
                   0
                 )

          from public.rr_rm_purchase_lines_v849_2c6 pl

          where pl.purchase_id=p_purchase_id
        ),

      updated_at=now()

    where h.purchase_id=p_purchase_id;


    insert into public.rr_rm_purchase_audit_v849_2c6
    (
      purchase_id,
      purchase_no,
      action_code,
      details
    )
    values
    (
      p_purchase_id,
      v_header.purchase_no,
      'DRAFT_LINES_REPLACED',

      jsonb_build_object(
        'line_count',
        v_line_count
      )
    );


    return jsonb_build_object(
      'ok',true,
      'purchase_id',p_purchase_id,
      'status','DRAFT',
      'line_count',v_line_count
    );

end;
$function$
;

CREATE OR REPLACE FUNCTION public.rr_rm_finish_purchase_test71(p_purchase_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare h record;s record;party uuid;purchase_ledger uuid;tx jsonb;costj jsonb;receipt_line record;diff numeric;amt numeric;note_tx uuid;net numeric;
begin
 perform public.rr_rm_assert_operator_test71();
 select * into h from public.rr_rm_purchase_header_v849_2c6 where purchase_id=p_purchase_id for update;
 if not found or h.data_mode<>'TEST' then raise exception 'TEST Readymade purchase required.'; end if;
 party:=public.rr_supplier_ledger_resolve_v806(h.supplier_name);
 select l.id into purchase_ledger from public.rr_ledgers_v805 l join public.rr_account_categories_v805 c on c.id=l.category_id where l.ledger_code='RM_GARMENT_PURCHASE' and l.is_active order by l.created_at limit 1;
 if purchase_ledger is null then raise exception 'Readymade Purchase account mapping required.'; end if;
 for s in select * from public.rr_rm_stock_v849_2c6 where source_purchase_id=p_purchase_id order by lot_no loop
 perform public.rr_rm_sync_trade_stock_to_fg_v849(s.stock_id);
 insert into public.rr_fg_products_v787(lot_no,full_item_name,short_item_name,sale_rate,image_url,active)
 values(s.lot_no,s.item_name,s.item_name,0,s.final_image_url,true)
 on conflict(lot_no) do update set full_item_name=excluded.full_item_name,short_item_name=excluded.short_item_name,image_url=excluded.image_url;
 end loop;
 if not exists(select 1 from public.rr_account_transactions_v805 where source_module='READYMADE_PURCHASE' and source_record_id=p_purchase_id::text and data_mode=h.data_mode and status<>'REVERSED') then
 tx:=public.rr_accounts_mirror_post_v806('PURCHASE',h.total_purchase_amount,jsonb_build_array(jsonb_build_object('ledger_id',purchase_ledger,'dr',h.total_purchase_amount,'cr',0),jsonb_build_object('ledger_id',party,'dr',0,'cr',h.total_purchase_amount)),'READYMADE_PURCHASE',p_purchase_id::text,party,coalesce(h.bill_no_test71,h.purchase_no),h.purchase_date,'Readymade garments purchase',h.data_mode);
 update public.rr_rm_purchase_header_v849_2c6 set supplier_ledger_id_test71=party,account_transaction_id_test71=(tx->>'transaction_id')::uuid where purchase_id=p_purchase_id;
 end if;

 -- Financial base is the original party bill; physical stock is received PCS.
 for receipt_line in select * from public.rr_rm_purchase_lines_v849_2c6 where purchase_id=p_purchase_id order by lot_no for update loop
  diff:=receipt_line.qty-coalesce(receipt_line.bill_qty_test71,receipt_line.qty);
  amt:=abs(round(receipt_line.qty*receipt_line.purchase_rate,2)-round(coalesce(receipt_line.bill_qty_test71,receipt_line.qty)*receipt_line.purchase_rate,2));
  if diff<>0 and amt>0 and receipt_line.receipt_note_transaction_id_test71 is null then
   tx:=public.rr_accounts_mirror_post_v806(case when diff<0 then 'PURCHASE_DEBIT_NOTE' else 'PURCHASE_CREDIT_NOTE' end,amt,
    case when diff<0 then jsonb_build_array(jsonb_build_object('ledger_id',party,'dr',amt,'cr',0),jsonb_build_object('ledger_id',purchase_ledger,'dr',0,'cr',amt))
    else jsonb_build_array(jsonb_build_object('ledger_id',purchase_ledger,'dr',amt,'cr',0),jsonb_build_object('ledger_id',party,'dr',0,'cr',amt)) end,
    case when diff<0 then 'READYMADE_RECEIPT_SHORT_DEBIT' else 'READYMADE_RECEIPT_EXCESS_CREDIT' end,receipt_line.purchase_line_id::text,party,coalesce(h.bill_no_test71,h.purchase_no),h.purchase_date,
    concat('Readymade ',receipt_line.lot_no,' · Party bill ',coalesce(receipt_line.bill_qty_test71,receipt_line.qty),' PCS · Received ',receipt_line.qty,' PCS · ',case when diff<0 then 'SHORT' else 'EXCESS' end,' ',abs(diff),' PCS @ ',receipt_line.purchase_rate),h.data_mode);
   note_tx:=(tx->>'transaction_id')::uuid;
   update public.rr_rm_purchase_lines_v849_2c6 set receipt_note_transaction_id_test71=note_tx where purchase_line_id=receipt_line.purchase_line_id;
  end if;
 end loop;
 -- Abort confirmation if stock, financial link, report mapping or supplier value diverges.
 if exists(select 1 from public.rr_rm_purchase_lines_v849_2c6 l left join public.rr_rm_stock_v849_2c6 stock_check on stock_check.source_purchase_line_id=l.purchase_line_id
    where l.purchase_id=p_purchase_id and (stock_check.stock_id is null or stock_check.qty_received<>l.qty or stock_check.purchase_rate<>l.purchase_rate
    or (l.qty<>coalesce(l.bill_qty_test71,l.qty) and abs(round(l.qty*l.purchase_rate,2)-round(coalesce(l.bill_qty_test71,l.qty)*l.purchase_rate,2))>0 and l.receipt_note_transaction_id_test71 is null))) then
   raise exception 'Purchase receipt could not reconcile. No changes saved; please retry.';
 end if;
 select coalesce(sum(p.cr_amount-p.dr_amount),0) into net from public.rr_account_transactions_v805 t join public.rr_account_postings_v805 p on p.transaction_id=t.id
 where p.ledger_id=party and t.data_mode=h.data_mode and t.status='POSTED' and
 ((t.source_module='READYMADE_PURCHASE' and t.source_record_id=p_purchase_id::text) or
 (t.source_module in ('READYMADE_RECEIPT_SHORT_DEBIT','READYMADE_RECEIPT_EXCESS_CREDIT') and t.source_record_id in(select purchase_line_id::text from public.rr_rm_purchase_lines_v849_2c6 where purchase_id=p_purchase_id)));
 if net<>(select sum(round(qty*purchase_rate,2)) from public.rr_rm_purchase_lines_v849_2c6 where purchase_id=p_purchase_id) then
  raise exception 'Supplier account could not reconcile with received value. No changes saved.';
 end if;
 if not exists(select 1 from public.rr_account_report_map_v806 m join public.rr_ledgers_v805 a on a.category_id=(select id from public.rr_account_categories_v805 where category_code=m.category_code) where a.id=purchase_ledger and m.is_active and m.report_type='PROFIT_LOSS' and m.report_section='PURCHASE') or
 not exists(select 1 from public.rr_account_reporting_base_v806 where ledger_id=party and source_module='READYMADE_PURCHASE' and source_record_id=p_purchase_id::text and report_type='BALANCE_SHEET' and report_section in('LIABILITY','CURRENT_LIABILITY')) then
  raise exception 'Purchase financial report mapping incomplete. No changes saved.';
 end if;

 return jsonb_build_object('ok',true);
end $function$
;

create or replace function public.rr_rm_receipt_summary_test71(p_purchase_id uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $function$
declare h record;outj jsonb;
begin
 perform public.rr_rm_assert_operator_test71();
 select * into h from public.rr_rm_purchase_header_v849_2c6 where purchase_id=p_purchase_id;
 if not found or h.data_mode<>'TEST' then raise exception 'TEST Readymade purchase required.';end if;
 select coalesce(jsonb_agg(jsonb_build_object('lot_no',l.lot_no,'bill_qty',coalesce(l.bill_qty_test71,l.qty),'received_qty',l.qty,
  'difference_qty',l.qty-coalesce(l.bill_qty_test71,l.qty),'purchase_rate',l.purchase_rate,
  'bill_value',round(coalesce(l.bill_qty_test71,l.qty)*l.purchase_rate,2),'received_value',round(l.qty*l.purchase_rate,2),
  'note_type',case when l.qty<coalesce(l.bill_qty_test71,l.qty) then 'DEBIT_NOTE' when l.qty>coalesce(l.bill_qty_test71,l.qty) then 'CREDIT_NOTE' else 'MATCHED' end,
  'note_amount',abs(round(l.qty*l.purchase_rate,2)-round(coalesce(l.bill_qty_test71,l.qty)*l.purchase_rate,2)),
  'account_transaction_id',l.receipt_note_transaction_id_test71,'voucher_no',t.voucher_no) order by l.lot_no),'[]') into outj
 from public.rr_rm_purchase_lines_v849_2c6 l left join public.rr_account_transactions_v805 t on t.id=l.receipt_note_transaction_id_test71 where l.purchase_id=p_purchase_id;
 return jsonb_build_object('purchase_id',p_purchase_id,'bill_no',h.bill_no_test71,'status',h.status,'lines',outj,'bill_value',h.total_purchase_amount,'received_value',(select sum(round(qty*purchase_rate,2)) from public.rr_rm_purchase_lines_v849_2c6 where purchase_id=p_purchase_id));
end $function$;
revoke all on function public.rr_rm_receipt_summary_test71(uuid) from public,anon;
grant execute on function public.rr_rm_receipt_summary_test71(uuid) to authenticated;
create or replace function public.rr_rm_stock_receipt_test71(p_stock_id uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $function$
declare pid uuid;
begin
 perform public.rr_rm_assert_operator_test71();
 select source_purchase_id into pid from public.rr_rm_stock_v849_2c6 where stock_id=p_stock_id and data_mode='TEST';
 if pid is null then raise exception 'Readymade stock not found.';end if;
 return public.rr_rm_receipt_summary_test71(pid);
end $function$;
revoke all on function public.rr_rm_stock_receipt_test71(uuid) from public,anon;
grant execute on function public.rr_rm_stock_receipt_test71(uuid) to authenticated;
revoke all on function public.rr_rm_finish_purchase_test71(uuid) from public,anon;
CREATE OR REPLACE FUNCTION public.rr_rm_chat_save_test71(p_purchase_id uuid, p_supplier_name text, p_bill_no text, p_purchase_date date, p_lines jsonb, p_post boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare j jsonb;pid uuid;x jsonb;s record;costj jsonb;notes jsonb:='[]'::jsonb;h record;rate numeric;
begin
 perform public.rr_rm_assert_operator_test71();
 if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines)=0 then raise exception 'At least one garment required.';end if;
 for x in select value from jsonb_array_elements(p_lines) loop
  if nullif(trim(x->>'category'),'') is null then raise exception 'Garment category required.';end if;
  if coalesce(x->>'final_image_url','') !~ '^https?://' then raise exception 'Final garment image required.';end if;
  if (x->>'qty')::numeric::text in ('NaN','Infinity','-Infinity') or (x->>'purchase_rate')::numeric::text in ('NaN','Infinity','-Infinity') then raise exception 'Valid quantity and purchase rate required.';end if;
  rate:=nullif(x->>'final_rate','')::numeric;
  if rate is not null and (rate<0 or rate::text in ('NaN','Infinity','-Infinity')) then raise exception 'Valid final sales rate required.';end if;
 end loop;
 if p_purchase_id is not null then
  select * into h from public.rr_rm_purchase_header_v849_2c6 where purchase_id=p_purchase_id for update;
  if h.status='POSTED' then return jsonb_build_object('ok',true,'purchase_id',p_purchase_id,'status','POSTED','duplicate_blocked',true);end if;
 end if;
 j:=public.rr_rm_purchase_save_test71(p_purchase_id,p_supplier_name,p_bill_no,p_purchase_date,p_lines,false);
 pid:=(j->>'purchase_id')::uuid;
 for x in select value from jsonb_array_elements(p_lines) loop
  update public.rr_rm_purchase_lines_v849_2c6 set chat_details_test71=jsonb_build_object('category',trim(x->>'category'),'size_text',trim(x->>'size_text'),'colours_text',trim(x->>'colours_text'),'cloth_name',trim(x->>'cloth_name'),'art_no',trim(x->>'art_no'),'caption_note',trim(x->>'caption_note'),'final_rate',nullif(x->>'final_rate','')::numeric) where purchase_id=pid and lot_no=trim(x->>'lot_no');
 end loop;
 if p_post then
  j:=public.rr_rm_purchase_post_v849_2c6(pid);
  for s in select st.*,l.chat_details_test71 details from public.rr_rm_stock_v849_2c6 st join public.rr_rm_purchase_lines_v849_2c6 l on l.purchase_line_id=st.source_purchase_line_id where st.source_purchase_id=pid loop
   insert into public.rr_web_window_lot_profile_v9329(data_mode,lot_no,item_name,category,size_text,cloth_name,art_no)
   values('TEST',s.lot_no,s.item_name,s.details->>'category',s.details->>'size_text',s.details->>'cloth_name',s.details->>'art_no')
   on conflict(data_mode,lot_no) do update set item_name=excluded.item_name,category=excluded.category,size_text=excluded.size_text,cloth_name=excluded.cloth_name,art_no=excluded.art_no,updated_at=now();
   update public.rr_fg_products_v787 set size_text=s.details->>'size_text' where lot_no=s.lot_no;
   rate:=nullif(s.details->>'final_rate','')::numeric;
   if rate is not null then
    costj:=public.rr_rm_costing_test71(s.lot_no,'TEST');
    if coalesce((costj->>'costing_complete')::boolean,false) and coalesce(public.rr_costing_user_scope_v760(null)->>'effective_role','') in('OWNER','SUPER_ADMIN') then
     perform public.rr_rm_approve_rate_test71(s.lot_no,rate,'Readymade Real Chat purchase final rate');
    else notes:=notes||jsonb_build_array(s.lot_no||': final rate awaiting complete costing / Owner approval');end if;
   end if;
  end loop;
 end if;
 return j||jsonb_build_object('purchase_id',pid,'rate_notes',notes,'receipt',public.rr_rm_receipt_summary_test71(pid));
end $function$
;
