CREATE OR REPLACE FUNCTION public.rr_web_window_cards_v9329(p_search text DEFAULT NULL::text, p_category text DEFAULT NULL::text, p_stock_status text DEFAULT NULL::text, p_data_mode text DEFAULT 'TEST'::text, p_limit integer DEFAULT 60, p_offset integer DEFAULT 0)
 RETURNS TABLE(lot_no text, short_item_name text, full_item_name text, size_text text, sale_rate numeric, available_qty integer, pipeline_qty integer, stock_status text, cb_no text, art_no text, print_no text, metal_id_no text, cloth_name text, gsm numeric, item_name text, sleeves text, category text, caption text, primary_image_url text, image_count integer, hidden_image_count integer, media jsonb, search_rank integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with stock as (
  select lot_no,
         max(short_item_name) short_item_name,
         sum(available_qty)::int available_qty,
         max(sale_rate) sale_rate,
         max(data_mode) data_mode
  from public.rr_fg_stock_balance_v787
  where data_mode=coalesce(p_data_mode,'TEST')
  group by lot_no
), pipe as (
  select lot_no, sum(qty)::int pipeline_qty
  from public.rr_fg_boxes_v787
  where data_mode=coalesce(p_data_mode,'TEST')
    and status in ('PACK_DRAFT','READY_DESPATCH','IN_TRANSIT')
  group by lot_no
), media as (
  select m.lot_no,
         count(*)::int image_count,
         (array_agg(coalesce(m.image_url,m.storage_path) order by coalesce(m.variant_no,0), m.published_at nulls last))[1] primary_image_url,
         jsonb_agg(jsonb_build_object(
           'media_id',m.media_id,
           'variant_no',m.variant_no,
           'image_url',m.image_url,
           'storage_path',m.storage_path,
           'caption',m.caption,
           'customer_caption',m.customer_caption
         ) order by coalesce(m.variant_no,0), m.published_at nulls last) media
  from public.rr_fg_webstore_media_v808 m
  where m.data_mode=coalesce(p_data_mode,'TEST')
  group by m.lot_no
), base as (
  select coalesce(s.lot_no,p.lot_no,pr.lot_no) lot_no,
         coalesce(s.short_item_name, pr.short_item_name, pr.lot_no) short_item_name,
         coalesce(pr.full_item_name, s.short_item_name, pr.lot_no) full_item_name,
         coalesce(nullif(array_to_string(cl.size_set,' / '),''), nullif(array_to_string(pl.selected_sizes,' / '),''), nullif(pl.size_combo,''), nullif(trim(w.size_text),''), nullif(trim(pr.size_text),'')) size_text,
         coalesce(q.final_sale_rate, pr.sale_rate) sale_rate,
         coalesce(s.available_qty,0)::int available_qty,
         coalesce(p.pipeline_qty,0)::int pipeline_qty,
         w.cb_no,w.art_no,w.print_no,w.metal_id_no,w.cloth_name,w.gsm,
         coalesce(w.item_name, pr.short_item_name, s.short_item_name) item_name,
         w.sleeves,
         coalesce(nullif(trim(w.category),''), ac.category_name, nullif(trim(am.category),''),'') category,
         coalesce(w.caption_override, med.media->0->>'customer_caption', med.media->0->>'caption') caption_base,
         coalesce(med.primary_image_url,tr.final_image_url) primary_image_url,
         coalesce(med.image_count,case when tr.final_image_url is not null then 1 else 0 end)::int image_count,
         coalesce(med.media,case when tr.final_image_url is not null then jsonb_build_array(jsonb_build_object('image_url',tr.final_image_url,'caption',tr.item_name)) else '[]'::jsonb end) media
  from stock s
  full join pipe p on p.lot_no=s.lot_no
  full join public.rr_fg_products_v787 pr on pr.lot_no=coalesce(s.lot_no,p.lot_no)
  left join public.rr_web_window_lot_profile_v9329 w on w.lot_no=coalesce(s.lot_no,p.lot_no,pr.lot_no) and w.data_mode=coalesce(p_data_mode,'TEST')
  left join public.rrq_lot_rates_v9300 q on q.lot_no=coalesce(s.lot_no,p.lot_no,pr.lot_no) and q.data_mode=coalesce(p_data_mode,'TEST')
  left join public.rr_rm_stock_v849_2c6 tr on tr.lot_no=coalesce(s.lot_no,p.lot_no,pr.lot_no) and tr.data_mode=coalesce(p_data_mode,'TEST')
  left join public.rr_upm_lot_registry lr on lr.lot_no=coalesce(s.lot_no,p.lot_no,pr.lot_no)
  left join public.rr_cutting_lots_v3 cl on lr.source_table='rr_cutting_lots_v3' and cl.id::text=lr.source_id
  left join public.rr_production_lots pl on lr.source_table='rr_production_lots' and pl.id::text=lr.source_id
  left join public.rr_art_master am on am.id::text=lr.art_id
  left join public.rr_art_categories ac on ac.id=am.art_category_id
  left join media med on med.lot_no=coalesce(s.lot_no,p.lot_no,pr.lot_no)
)
select b.lot_no,
       b.short_item_name,
       b.full_item_name,
       b.size_text,
       b.sale_rate,
       b.available_qty,
       b.pipeline_qty,
       case when b.available_qty>=108 then 'IN_STOCK'
            when b.available_qty between 1 and 107 then 'LOW_STOCK'
            when b.available_qty=0 and b.pipeline_qty>0 then 'COMING_SOON'
            else 'SOLD_OUT' end stock_status,
       b.cb_no,b.art_no,b.print_no,b.metal_id_no,b.cloth_name,b.gsm,b.item_name,b.sleeves,
       b.category,
       coalesce(b.caption_base,
         '📦 Lot No: '||b.lot_no||chr(10)||
         '🧵 Cloth Name: '||coalesce(b.cloth_name,'')||chr(10)||
         '⚖️ GSM: '||coalesce(b.gsm::text,'')||chr(10)||
         '👕 Item Name: '||coalesce(b.item_name,b.short_item_name,'')||chr(10)||
         '📏 Size: '||coalesce(b.size_text,'')||chr(10)||
         '🧥 Sleeves: '||coalesce(b.sleeves,'')||chr(10)||
         '💰 Sale Rate: '||case when b.sale_rate is null then '—' else '₹'||b.sale_rate::text||'/pcs' end||chr(10)||chr(10)||
         '✨ New Arrival'||chr(10)||
         case when b.available_qty>=108 then '✅ In Stock' when b.available_qty between 1 and 107 then '⚠️ Low Stock' when b.available_qty=0 and b.pipeline_qty>0 then '⏳ Coming Soon' else '❌ Sold Out' end||chr(10)||
         '🏷️ Category: '||coalesce(b.category,'')||chr(10)||
         '🎨 Colours: '
       ) caption,
       b.primary_image_url,
       b.image_count,
       greatest(b.image_count-1,0) hidden_image_count,
       b.media,
       case
        when coalesce(p_search,'')='' then 100
        when b.lot_no=trim(p_search) then 0
        when b.lot_no ilike trim(p_search)||'%' then 1
        when concat_ws(' ',b.lot_no,b.cb_no,b.art_no,b.print_no,b.metal_id_no,b.short_item_name,b.full_item_name,b.item_name) ilike '%'||trim(p_search)||'%' then 2
        else 9 end search_rank
from base b
where (coalesce(p_search,'')='' or concat_ws(' ',b.lot_no,b.cb_no,b.art_no,b.print_no,b.metal_id_no,b.short_item_name,b.full_item_name,b.item_name) ilike '%'||trim(p_search)||'%')
  and (coalesce(p_category,'')='' or lower(coalesce(b.category,''))=lower(p_category))
  and (coalesce(p_stock_status,'')='' or lower(case when b.available_qty>=108 then 'IN_STOCK' when b.available_qty between 1 and 107 then 'LOW_STOCK' when b.available_qty=0 and b.pipeline_qty>0 then 'COMING_SOON' else 'SOLD_OUT' end)=lower(p_stock_status))
order by search_rank, b.lot_no
limit greatest(1,least(coalesce(p_limit,60),150)) offset greatest(0,coalesce(p_offset,0));
$function$
;

create or replace function public.rr_rm_costing_test71(p_lot_no text,p_data_mode text default 'TEST') returns jsonb language plpgsql stable security definer set search_path=public as $$
declare s record;h record;ps date;pe date;shared jsonb;ratio numeric;pcs numeric;oh numeric:=0;sal numeric:=0;rows jsonb;outj jsonb;private_ok boolean;
begin
 perform public.rr_fg_assert_user_v787();
 select * into s from public.rr_rm_stock_v849_2c6 where upper(trim(lot_no))=upper(trim(p_lot_no)) and data_mode=upper(p_data_mode);
 if not found then raise exception 'Readymade lot not found.'; end if;
 private_ok:=coalesce(public.rr_costing_user_scope_v760(null)->>'effective_role','') in('OWNER','SUPER_ADMIN');
 if s.costing_snapshot_test71 is not null then outj:=s.costing_snapshot_test71;
 else
 select * into h from public.rr_rm_purchase_header_v849_2c6 where purchase_id=s.source_purchase_id;
 ps:=date_trunc('month',h.purchase_date)::date;pe:=(ps+interval '1 month - 1 day')::date;
 shared:=public.rr_shared_business_allocation_v669(ps,pe,p_data_mode);
 pcs:=coalesce((shared->>'readymade_inward_pcs')::numeric,0);
 ratio:=coalesce((shared->>'readymade_inward_value')::numeric,0)/nullif(coalesce((shared->>'manufacturing_stock_in_value')::numeric,0)+coalesce((shared->>'readymade_inward_value')::numeric,0),0);
 sal:=coalesce((shared->>'readymade_salary_per_pc')::numeric,0);
 -- Heads retain their identity; salary is sourced ONLY from canonical salary profiles.
 -- Actual Accounts entries are used only when no corresponding expense-pool head exists.
 with pool as (
 select upper(expense_code) code,expense_name label,business_stream, sum(amount*greatest(0,least(period_end,pe)-greatest(period_start,ps)+1)::numeric/greatest(1,period_end-period_start+1)) amount
 from public.rr_cost_expense_pool_v850 where data_mode=upper(p_data_mode) and is_active and period_start<=pe and period_end>=ps
 and upper(business_stream) in('ALL','TRADING','READYMADE') and upper(expense_code) not like '%SALARY%'
 group by upper(expense_code),expense_name,business_stream
 ),acct as (
 select c.category_code code,c.category_name label,'ALL'::text business_stream,sum(p.dr_amount-p.cr_amount) amount
 from public.rr_account_transactions_v805 t join public.rr_account_postings_v805 p on p.transaction_id=t.id
 join public.rr_ledgers_v805 l on l.id=p.ledger_id join public.rr_account_categories_v805 c on c.id=l.category_id
 where t.data_mode=upper(p_data_mode) and t.status='POSTED' and coalesce(t.bill_date,t.transaction_datetime::date) between ps and pe
 and c.category_code in('ELECTRICITY_EXPENSE','WATER_EXPENSE','RENT_EXPENSE','TELEPHONE_INTERNET','STATIONERY_EXPENSE','ADMIN_OFFICE_EXPENSE','SELLING_DISTRIBUTION','BANK_CHARGES','PROFESSIONAL_FEES','REPAIR_MAINTENANCE','OTHER_EXPENSE')
 and not exists(select 1 from pool e where e.code=c.category_code) group by c.category_code,c.category_name
 ),allheads as(select * from pool union all select * from acct),a as(
 select *,amount*case when upper(business_stream)='ALL' then coalesce(ratio,0) else 1 end/nullif(pcs,0) per_pc from allheads)
 select coalesce(jsonb_agg(jsonb_build_object('head',code,'label',label,'period_amount',amount,'business_stream',business_stream,'per_pc',round(per_pc,6)) order by code),'[]'::jsonb),coalesce(sum(per_pc),0) into rows,oh from a;
 outj:=jsonb_build_object('ok',pcs>0 and shared->>'state'='READY','costing_complete',pcs>0 and shared->>'state'='READY','version','TEST71_READYMADE','path','READYMADE_WEIGHTED_COST_TEST71','lot_no',s.lot_no,'qty',s.qty_received,'period_start',ps,'period_end',pe,'purchase_cost_per_pc',s.purchase_rate,'owner_margin_per_pc',22,'salary_per_pc',sal,'overhead_per_pc',oh,'overhead_heads',rows,'salary_allocation',shared,'total_cost_per_pc',s.purchase_rate+sal+oh,'source_rate',round(s.purchase_rate+sal+oh+22,0),'calculated_sale_rate',s.purchase_rate+sal+oh+22,'frozen',false);
 end if;
 if private_ok then return outj||jsonb_build_object('qty',s.available_qty); end if;
 return jsonb_build_object('ok',outj->'ok','costing_complete',outj->'costing_complete','lot_no',s.lot_no,'qty',s.available_qty,'source_rate',outj->'source_rate','calculated_sale_rate',outj->'source_rate','path',outj->'path','frozen',outj->'frozen');
end $$;

create or replace function public.rr_rm_finish_purchase_test71(p_purchase_id uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare h record;s record;party uuid;purchase_ledger uuid;tx jsonb;costj jsonb;
begin
 perform public.rr_rm_assert_operator_test71();
 select * into h from public.rr_rm_purchase_header_v849_2c6 where purchase_id=p_purchase_id for update;
 if not found or h.data_mode<>'TEST' then raise exception 'TEST Readymade purchase required.'; end if;
 party:=public.rr_supplier_ledger_resolve_v806(h.supplier_name);
 select l.id into purchase_ledger from public.rr_ledgers_v805 l join public.rr_account_categories_v805 c on c.id=l.category_id where c.category_code='OTHER_MATERIAL_PURCHASE' and l.is_active order by l.created_at limit 1;
 if purchase_ledger is null then raise exception 'Readymade Purchase account mapping required.'; end if;
 for s in select * from public.rr_rm_stock_v849_2c6 where source_purchase_id=p_purchase_id order by lot_no loop
 perform public.rr_rm_sync_trade_stock_to_fg_v849(s.stock_id);
 insert into public.rr_fg_products_v787(lot_no,full_item_name,short_item_name,sale_rate,image_url,active)
 values(s.lot_no,s.item_name,s.item_name,null,s.final_image_url,true)
 on conflict(lot_no) do update set full_item_name=excluded.full_item_name,short_item_name=excluded.short_item_name,image_url=excluded.image_url;
 end loop;
 if not exists(select 1 from public.rr_account_transactions_v805 where source_module='READYMADE_PURCHASE' and source_record_id=p_purchase_id::text and data_mode=h.data_mode and status<>'REVERSED') then
 tx:=public.rr_accounts_mirror_post_v806('PURCHASE',h.total_purchase_amount,jsonb_build_array(jsonb_build_object('ledger_id',purchase_ledger,'dr',h.total_purchase_amount,'cr',0),jsonb_build_object('ledger_id',party,'dr',0,'cr',h.total_purchase_amount)),'READYMADE_PURCHASE',p_purchase_id::text,party,coalesce(h.bill_no_test71,h.purchase_no),h.purchase_date,'Readymade garments purchase',h.data_mode);
 update public.rr_rm_purchase_header_v849_2c6 set supplier_ledger_id_test71=party,account_transaction_id_test71=(tx->>'transaction_id')::uuid where purchase_id=p_purchase_id;
 end if;
 return jsonb_build_object('ok',true);
end $$;

create or replace function public.rr_rm_approve_rate_test71(p_lot_no text,p_final_rate numeric,p_reason text default null) returns jsonb language plpgsql security definer set search_path=public as $$
declare s record;j jsonb;r jsonb;
begin
 perform public.rr_rm_assert_operator_test71();
 if lower(public.rr_costing_user_scope_v760(null)->>'effective_role') not in('owner','super_admin','superadmin','admin') then raise exception 'Owner / Admin rate approval required.';end if;
 perform pg_advisory_xact_lock(hashtextextended('RM:'||upper(trim(p_lot_no))||':TEST',0));
 select * into s from public.rr_rm_stock_v849_2c6 where upper(trim(lot_no))=upper(trim(p_lot_no)) and data_mode='TEST' for update;
 if not found then raise exception 'Readymade lot not found.';end if;
 -- Freeze full private costing under owner scope; Admin can approve but cannot read it.
 if s.costing_snapshot_test71 is null then
 if lower(public.rr_costing_user_scope_v760(null)->>'effective_role') not in('owner','super_admin','superadmin') then raise exception 'Owner must finalize Readymade costing first.';end if;
 j:=public.rr_rm_costing_test71(s.lot_no,'TEST');
 if not coalesce((j->>'costing_complete')::boolean,false) then raise exception 'Monthly weighted allocation is pending.';end if;
 update public.rr_rm_stock_v849_2c6 set costing_snapshot_test71=j||jsonb_build_object('frozen',true,'frozen_at',now()) where stock_id=s.stock_id;
 end if;
 r:=public.rrq_apply_packing_rate_core_test71(s.lot_no,p_final_rate,'TEST',p_reason);
 update public.rr_rm_stock_v849_2c6 set target_sale_rate=p_final_rate,minimum_allowed_sale_rate=greatest(0,p_final_rate-max_customer_discount_per_pc),markup_mode='DEFAULT_22',markup_per_pc=22,sale_ready=true where stock_id=s.stock_id;
 return r;
end $$;

CREATE OR REPLACE FUNCTION public.rr_rm_purchase_post_v849_2c6(p_purchase_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$

declare
    v_header record;

    v_line record;

    v_line_count integer;

begin
    perform public.rr_rm_assert_operator_test71();

    select *
    into v_header

    from public.rr_rm_purchase_header_v849_2c6

    where purchase_id=p_purchase_id

    for update;


    if not found
    then
      raise exception
        'ReadyMade purchase not found.';
    end if;


    if v_header.status='POSTED'
    then

      return jsonb_build_object(

        'ok',true,

        'purchase_id',
          v_header.purchase_id,

        'purchase_no',
          v_header.purchase_no,

        'status',
          'POSTED',

        'stock_effect_applied',
          false,

        'reason',
          'ALREADY_POSTED'

      );

    end if;


    if v_header.status<>'DRAFT'
    then
      raise exception
        'Only DRAFT purchase may be posted.';
    end if;


    select count(*)
    into v_line_count

    from public.rr_rm_purchase_lines_v849_2c6 pl

    where pl.purchase_id=p_purchase_id;


    if v_line_count<=0
    then
      raise exception
        'At least one purchase line required.';
    end if;


    if exists(

      select 1

      from public.rr_rm_purchase_lines_v849_2c6 pl

      where pl.purchase_id=p_purchase_id

        and (
             pl.qty<=0
          or pl.purchase_rate<=0
          or pl.markup_per_pc<>22
          or pl.max_customer_discount_per_pc<>10
          or pl.final_image_url is null
        )

    )
    then
      raise exception
        'ReadyMade Qty / Rate / Markup / Final Image validation failed.';
    end if;


    -- --------------------------------------------------------
    -- GLOBAL LOT COLLISION CHECK
    -- --------------------------------------------------------

    for v_line in

      select pl.*

      from public.rr_rm_purchase_lines_v849_2c6 pl

      where pl.purchase_id=p_purchase_id

      order by pl.lot_no

    loop

      perform
        public.rr_rm_assert_lot_available_v849(
          v_line.lot_no
        );

    end loop;


    -- --------------------------------------------------------
    -- CREATE TRADED STOCK
    -- --------------------------------------------------------

    for v_line in

      select pl.*

      from public.rr_rm_purchase_lines_v849_2c6 pl

      where pl.purchase_id=p_purchase_id

      order by pl.lot_no

    loop

      insert into public.rr_rm_stock_v849_2c6
      (
        lot_no,
        source_purchase_id,
        source_purchase_line_id,
        item_name,
        source_type,
        purchase_rate,
        markup_mode,
        markup_per_pc,
        max_customer_discount_per_pc,
        target_sale_rate,
        minimum_allowed_sale_rate,
        qty_received,
        qty_sold,
        final_image_url,
        sale_ready,
        data_mode
      )
      values
      (
        v_line.lot_no,
        p_purchase_id,
        v_line.purchase_line_id,
        v_line.item_name,
        'TRADED',
        v_line.purchase_rate,
        v_line.markup_mode,
        v_line.markup_per_pc,
        v_line.max_customer_discount_per_pc,
        v_line.target_sale_rate,
        v_line.minimum_allowed_sale_rate,
        v_line.qty,
        0,
        v_line.final_image_url,
        false,
        'TEST'
      );

    end loop;


    -- --------------------------------------------------------
    -- STOCK RECONCILIATION
    -- --------------------------------------------------------

    if
    (
      select coalesce(
               sum(st.qty_received),
               0
             )

      from public.rr_rm_stock_v849_2c6 st

      where st.source_purchase_id=p_purchase_id
    )
    <>
    (
      select coalesce(
               sum(pl.qty),
               0
             )

      from public.rr_rm_purchase_lines_v849_2c6 pl

      where pl.purchase_id=p_purchase_id
    )
    then

      raise exception
        'ReadyMade stock reconciliation failed.';

    end if;


    -- --------------------------------------------------------
    -- REGISTER UNIVERSAL LOT IDENTITY
    -- --------------------------------------------------------

    insert into public.rr_universal_lot_registry_v849
    (
      lot_no,
      normalized_lot_no,
      source_type,
      source_internal_id,
      data_mode
    )

    select
        st.lot_no,

        upper(
          trim(
            st.lot_no
          )
        ),

        'TRADED',

        st.stock_id::text,

        st.data_mode

    from public.rr_rm_stock_v849_2c6 st

    where st.source_purchase_id=p_purchase_id

    on conflict(
      normalized_lot_no,
      data_mode
    )

    do update set
      lot_no=excluded.lot_no,
      source_type='TRADED',
      source_internal_id=excluded.source_internal_id,
      updated_at=now();


    -- --------------------------------------------------------
    -- FINAL POST
    -- --------------------------------------------------------

    perform public.rr_rm_finish_purchase_test71(p_purchase_id);

    update public.rr_rm_purchase_header_v849_2c6 h

    set
      status='POSTED',
      posted_at=now(),
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

      'POSTED_TO_TRADED_STOCK',

      jsonb_build_object(
        'line_count',
          v_line_count,

        'universal_lot_identity_registered',
          true
      )
    );


    return jsonb_build_object(

      'ok',true,

      'purchase_id',
        p_purchase_id,

      'purchase_no',
        v_header.purchase_no,

      'status',
        'POSTED',

      'stock_effect_applied',
        true,

      'universal_lot_identity_registered',
        true

    );

end;
$function$
;

CREATE OR REPLACE FUNCTION public.rr_fg_save_pi_v787(p_pi_id uuid, p_buyer_name text, p_dispatch_details text, p_lines jsonb, p_value_added_pct numeric DEFAULT 0, p_packing_other numeric DEFAULT 0, p_finalize boolean DEFAULT false, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    pid uuid;
    bid uuid;
    pi text;
    cpi text;
    ver int;
    sub numeric;
    raw numeric;
    grand numeric;
    ln jsonb;
    avail int;
    v_rate numeric;
    v_trade jsonb;
    v_actor uuid;
    v_serial integer:=0;
    v_party_discount numeric;
begin

    perform rr_fg_assert_user_v787();

    v_actor:=coalesce(
      auth.uid(),
      'af915a18-3823-48df-b039-1e4c7a88479b'::uuid
    );

    if p_packing_other<0
       or jsonb_typeof(p_lines)<>'array'
       or jsonb_array_length(p_lines)=0
    then
        raise exception 'Valid PI lines required';
    end if;

    select id
    into bid
    from rr_buyers_v787
    where lower(buyer_name)=lower(trim(p_buyer_name));

    if bid is null then
        insert into rr_buyers_v787(buyer_name)
        values(trim(p_buyer_name))
        returning id into bid;
    end if;

    if p_pi_id is null then

        pi:=rr_fg_next_no_v787(
          'PI',
          p_data_mode,
          case when p_data_mode='TEST' then 'TPI' else 'PI' end
        );

        insert into rr_fg_pi_v787
        (
            pi_no,
            buyer_id,
            buyer_snapshot,
            dispatch_details,
            data_mode
        )
        select
            pi,
            b.id,
            jsonb_build_object(
                'buyer_name',b.buyer_name,
                'contact_no',b.contact_no,
                'address',b.address,
                'gst_no',b.gst_no
            ),
            p_dispatch_details,
            p_data_mode
        from rr_buyers_v787 b
        where b.id=bid
        returning id into pid;

    else

        select id,version_no
        into pid,ver
        from rr_fg_pi_v787
        where id=p_pi_id
          and status='DRAFT'
          and data_mode=p_data_mode
        for update;

        if pid is null then
            raise exception 'Editable PI not found';
        end if;

        update rr_fg_pi_v787
        set
            version_no=version_no+1,
            buyer_id=bid,
            dispatch_details=p_dispatch_details,
            updated_at=now()
        where id=pid;

        delete from rr_fg_pi_lines_v787
        where pi_id=pid;

    end if;


    if upper(p_data_mode)='TEST' then
      perform pg_advisory_xact_lock(hashtextextended('RM:'||upper(trim(x->>'lot_no'))||':'||p_data_mode,0))
      from jsonb_array_elements(p_lines) x where x->>'stock_type'='TRADED' order by upper(trim(x->>'lot_no'));
      if p_finalize and exists(select 1 from (select upper(trim(x->>'lot_no')) lot,sum((x->>'qty')::integer) qty from jsonb_array_elements(p_lines) x where x->>'stock_type'='TRADED' group by upper(trim(x->>'lot_no'))) g where g.qty>
        coalesce((select sum(b.available_qty) from public.rr_fg_stock_balance_v787 b
        where upper(trim(b.lot_no))=g.lot and b.stock_type='TRADED' and b.data_mode=p_data_mode),0))
      then raise exception 'Readymade quantity exceeds available stock.'; end if;
    end if;

    for ln in
        select *
        from jsonb_array_elements(p_lines)
    loop

        if (ln->>'stock_type') not in(
            'REGULAR',
            'ASST',
            'TRADED'
        )
        or (ln->>'qty')::int<=0
        then
            raise exception 'Invalid PI line';
        end if;


        select coalesce(sum(available_qty),0)
        into avail
        from rr_fg_stock_balance_v787
        where upper(trim(lot_no))=
              upper(trim(ln->>'lot_no'))
          and stock_type=ln->>'stock_type'
          and data_mode=p_data_mode;


        if p_finalize
           and avail<(ln->>'qty')::int
        then
            raise exception 'Insufficient stock';
        end if;


        if ln->>'stock_type'='TRADED' then

            v_trade :=
              public.rr_trade_effective_rate_v849(
                ln->>'lot_no',
                p_buyer_name,
                p_data_mode
              );

            if lower(coalesce(public.rr_costing_user_scope_v760(null)->>'effective_role','')) not in('owner','super_admin','superadmin','admin','sales','accounts','account','manager') then raise exception 'Sales permission required.';end if;
            v_rate:=coalesce((ln->>'rate')::numeric,(v_trade->>'final_rate')::numeric);
            if v_rate<0 or v_rate::text in('NaN','Infinity','-Infinity') then raise exception 'Valid Readymade bill rate required.';end if;
            -- TEST71 party billing uses one flat party discount, including traded items.
            -- Read the default on the server; never authorize a discount from line JSON.
            if upper(p_data_mode)='TEST' and ln ? 'party_discount_per_piece' then
                select coalesce(allowed_discount_per_piece,0) into v_party_discount
                from public.rr_customers
                where lower(customer_name)=lower(trim(p_buyer_name)) and is_active is true
                order by updated_at desc limit 1;
                if v_party_discount is null or v_party_discount<0 or v_party_discount>10 then
                    raise exception 'Invalid customer flat discount.';
                end if;
                if coalesce((ln->>'gross_rate')::numeric,-1)<0 or (ln->>'gross_rate')::numeric::text in ('NaN','Infinity','-Infinity') then raise exception 'Valid Readymade bill rate required.'; end if;
                v_rate:=greatest(0,(ln->>'gross_rate')::numeric-v_party_discount);
            end if;

        else

            v_rate:=(ln->>'rate')::numeric;

        end if;


        v_serial:=v_serial+1;
        insert into rr_fg_pi_lines_v787
        (
            pi_id,
            lot_no,
            short_item_name,
            stock_type,
            qty,
            original_rate,
            final_rate,
            amount,
            serial_no
        )
        values
        (
            pid,
            ln->>'lot_no',
            coalesce(
              nullif(ln->>'short_item_name',''),
              ln->>'lot_no'
            ),
            ln->>'stock_type',
            (ln->>'qty')::int,
            v_rate,
            v_rate,
            (ln->>'qty')::int*v_rate,
            v_serial
        );

    end loop;


    select coalesce(sum(amount),0)
    into sub
    from rr_fg_pi_lines_v787
    where pi_id=pid;

    raw:=
      sub+
      (sub*p_value_added_pct/100)+
      p_packing_other;

    grand:=round(raw/10)*10;


    update rr_fg_pi_v787
    set
        value_added_pct=p_value_added_pct,
        packing_other=p_packing_other,
        sub_total=sub,
        round_off=grand-raw,
        grand_total=grand,
        updated_at=now()
    where id=pid;


    select version_no
    into ver
    from rr_fg_pi_v787
    where id=pid;


    insert into rr_fg_pi_versions_v787
    (
        pi_id,
        version_no,
        snapshot
    )
    select
        pid,
        ver,
        jsonb_build_object(
            'header',to_jsonb(p),
            'lines',
            (
                select jsonb_agg(to_jsonb(l))
                from rr_fg_pi_lines_v787 l
                where l.pi_id=pid
            )
        )
    from rr_fg_pi_v787 p
    where p.id=pid
    on conflict do nothing;


    if p_finalize then

        cpi:=rr_fg_next_no_v787(
          'CPI',
          p_data_mode,
          case when p_data_mode='TEST' then 'TCI' else 'CI' end
        );


        for ln in
            select to_jsonb(l)
            from rr_fg_pi_lines_v787 l
            where l.pi_id=pid
        loop

            insert into rr_fg_stock_ledger_v787
            (
                txn_type,
                ref_type,
                ref_id,
                lot_no,
                stock_type,
                location_code,
                qty_delta,
                rate,
                data_mode,
                created_by,
                meta
            )
            values
            (
                'CI_SALE',
                'CI_LINE',
                (ln->>'id')::uuid,
                ln->>'lot_no',
                ln->>'stock_type',
                null,
                -(ln->>'qty')::int,
                (ln->>'final_rate')::numeric,
                p_data_mode,
                v_actor,
                jsonb_build_object(
                    'pi_id',pid,
                    'source_type',
                    case
                      when ln->>'stock_type'='TRADED'
                      then 'TRADED'
                      else 'MANUFACTURED'
                    end
                )
            );

        end loop;


        update rr_fg_pi_v787
        set
            status='CI_FINAL',
            cpi_no=cpi,
            finalized_by=v_actor,
            finalized_at=now()
        where id=pid;

    end if;


    select pi_no
    into pi
    from rr_fg_pi_v787
    where id=pid;


    return jsonb_build_object(
        'pi_id',pid,
        'pi_no',pi,
        'cpi_no',cpi,
        'grand_total',grand
    );

end
$function$
;
