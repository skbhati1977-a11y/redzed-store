-- Art is a sale lookup; canonical stock and returns remain physical Lot based.
alter table public.rr_fg_pi_lines_v787 add column if not exists readymade_art_no_test71 text;
alter table public.rr_fg_pi_lines_v787 add column if not exists art_sale_key_test71 text;
alter table public.rr_pi_reservation_v9630 alter column pi_line_id drop not null;

create or replace function public.rr_rm_sale_lots_test71(p_art_no text default null,p_pi_id uuid default null)
returns table(lot_no text,art_no text,item_name text,available_qty numeric,purchase_date date,created_at timestamptz,image text,size_text text)
language plpgsql stable security definer set search_path=public as $fn$
begin
 perform public.rr_market_assert_sales_actor_v9420();
 return query select s.lot_no,upper(trim(l.chat_details_test71->>'art_no')),l.item_name,
 greatest(0,coalesce((select sum(b.available_qty) from public.rr_fg_stock_balance_v787 b where upper(trim(b.lot_no))=upper(trim(s.lot_no)) and b.stock_type='TRADED' and b.data_mode='TEST'),0)-
 coalesce((select sum(r.reserved_qty) from public.rr_pi_reservation_v9630 r where upper(trim(r.lot_no))=upper(trim(s.lot_no)) and r.stock_type='TRADED' and r.data_mode='TEST' and r.status in ('ACTIVE','CONFIRMED') and r.pi_id is distinct from p_pi_id),0))::numeric,
 h.purchase_date,l.created_at,s.final_image_url,l.chat_details_test71->>'size_text'
 from public.rr_rm_stock_v849_2c6 s join public.rr_rm_purchase_lines_v849_2c6 l on l.purchase_line_id=s.source_purchase_line_id
 join public.rr_rm_purchase_header_v849_2c6 h on h.purchase_id=l.purchase_id
 where s.data_mode='TEST' and h.status='POSTED' and s.sale_ready and (p_art_no is null or upper(trim(l.chat_details_test71->>'art_no'))=upper(trim(p_art_no)))
 order by h.purchase_date,l.created_at,s.lot_no;
end $fn$;
revoke all on function public.rr_rm_sale_lots_test71(text,uuid) from public,anon,authenticated;

create or replace function public.rr_rm_sale_allocate_test71(p_lines jsonb,p_pi_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public as $fn$
declare ln jsonb;r record;used jsonb:='{}';outlines jsonb:='[]';art text;remain integer;takeqty integer;key text;available numeric;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'Valid PI lines required';end if;
 -- Same locks as direct Lot sales and the PI reservation engine, in Lot order.
 for r in select distinct q.lot_no from public.rr_rm_sale_lots_test71(null,p_pi_id) q
 where exists(select 1 from jsonb_array_elements(p_lines) x where x->>'stock_type'='TRADED' and
 (upper(trim(x->>'art_no'))=q.art_no or (nullif(trim(x->>'art_no'),'') is null and upper(trim(x->>'lot_no'))=upper(trim(q.lot_no))))) order by q.lot_no loop
 perform pg_advisory_xact_lock(hashtextextended('RM:'||upper(trim(r.lot_no))||':TEST',0));
 perform pg_advisory_xact_lock(hashtextextended(upper(trim(r.lot_no))||'|TRADED|TEST',9630));
 end loop;
 for ln in select value from jsonb_array_elements(p_lines) loop
 if ln->>'stock_type'<>'TRADED' then outlines:=outlines||jsonb_build_array(ln);continue;end if;
 remain:=(ln->>'qty')::integer;
 if remain<=0 then raise exception 'Positive whole PCS required';end if;
 art:=nullif(upper(trim(ln->>'art_no')),'');key:=case when art is not null then gen_random_uuid()::text end;
 for r in select * from public.rr_rm_sale_lots_test71(art,p_pi_id) q
 where art is not null or upper(trim(q.lot_no))=upper(trim(ln->>'lot_no')) order by q.purchase_date,q.created_at,q.lot_no loop
 available:=greatest(0,r.available_qty-coalesce((used->>r.lot_no)::numeric,0));takeqty:=least(remain,available)::integer;
 if takeqty>0 then
 outlines:=outlines||jsonb_build_array(ln||jsonb_build_object('lot_no',r.lot_no,'qty',takeqty,'art_no',art,'art_sale_key',key));
 used:=jsonb_set(used,array[r.lot_no],to_jsonb(coalesce((used->>r.lot_no)::numeric,0)+takeqty));remain:=remain-takeqty;
 end if;
 exit when remain=0;
 end loop;
 if remain>0 then raise exception 'Readymade %: insufficient unreserved stock; short % PCS.',coalesce('Art '||art,'Lot '||(ln->>'lot_no')),remain;end if;
 end loop;
 return outlines;
end $fn$;
revoke all on function public.rr_rm_sale_allocate_test71(jsonb,uuid) from public,anon,authenticated;

create or replace function public.rr_rm_sale_search_test71(p_search text,p_pi_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public as $fn$
declare result jsonb;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 select coalesce(jsonb_agg(to_jsonb(q)),'[]') into result from (
 select 'ART:'||s.art_no lot_no,s.art_no, max(s.item_name) category,sum(s.available_qty) available_qty,
 (array_agg(s.image order by s.purchase_date desc,s.created_at desc))[1] thumbnail,
 (array_agg(s.size_text order by s.purchase_date desc,s.created_at desc))[1] sizes
 from public.rr_rm_sale_lots_test71(null,p_pi_id) s where nullif(s.art_no,'') is not null
 and (s.art_no ilike '%'||trim(replace(upper(p_search),'ART:',''))||'%' or s.item_name ilike '%'||trim(p_search)||'%')
 group by s.art_no having sum(s.available_qty)>0 order by s.art_no limit 20) q;
 return result;
end $fn$;
revoke all on function public.rr_rm_sale_search_test71(text,uuid) from public,anon;
grant execute on function public.rr_rm_sale_search_test71(text,uuid) to authenticated;

create or replace function public.rr_rm_sale_context_test71(p_art_no text,p_customer_name text,p_pi_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public as $fn$
declare r record;c jsonb;t jsonb;qty numeric;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 select * into r from public.rr_rm_sale_lots_test71(p_art_no,p_pi_id) where available_qty>0 order by purchase_date desc,created_at desc limit 1;
 if r.lot_no is null then raise exception 'Readymade Art unavailable or not approved.';end if;
 select sum(available_qty) into qty from public.rr_rm_sale_lots_test71(p_art_no,p_pi_id);
 c:=public.rr_pi_lot_context_v9517(r.lot_no,p_customer_name,'TEST');
 t:=public.rr_trade_effective_rate_v849(r.lot_no,p_customer_name,'TEST');
 return c||jsonb_build_object('art_no',upper(trim(p_art_no)),'reference_lot_no',r.lot_no,'available_qty',qty,'rrq_available',qty,'category',r.item_name,'image',r.image,'size_text',r.size_text,'approved_rate',t->'target_sale_rate','effective_rate',t->'target_sale_rate','rate_path','READYMADE_ART_FIFO');
end $fn$;
revoke all on function public.rr_rm_sale_context_test71(text,text,uuid) from public,anon;
grant execute on function public.rr_rm_sale_context_test71(text,text,uuid) to authenticated;

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
    v_input_lines jsonb;
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

    if upper(p_data_mode)='TEST' and exists(select 1 from jsonb_array_elements(p_lines) x where x->>'stock_type'='TRADED') then
      if p_pi_id is not null then perform 1 from public.rr_fg_pi_v787 where id=p_pi_id and status='DRAFT' and data_mode='TEST' for update; end if;
      p_lines:=public.rr_rm_sale_allocate_test71(p_lines,p_pi_id);
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

        -- Retain reservation/audit history while replacing canonical draft lines.
        update public.rr_pi_reservation_v9630 set status='RELEASED',released_at=now(),release_reason='PI draft replaced',updated_at=now(),pi_line_id=null where pi_id=pid;
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
            serial_no,readymade_art_no_test71,art_sale_key_test71
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
            v_serial,ln->>'art_no',ln->>'art_sale_key'
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


    if upper(p_data_mode)='TEST' and exists(select 1 from public.rr_fg_pi_lines_v787 where pi_id=pid and stock_type='TRADED') then
      if not p_finalize then perform public.rr_pi_reservation_sync_v9630(pid); end if;
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
CREATE OR REPLACE FUNCTION public.rr_fg_save_pi_commercial_test71(p_pi_id uuid, p_customer_name text, p_dispatch_details text, p_lines jsonb, p_value_added_pct numeric, p_freight_amount numeric DEFAULT 0, p_packing_other numeric DEFAULT 0, p_gst_pct numeric DEFAULT 0, p_finalize boolean DEFAULT false, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_customer public.rr_customers%rowtype;
  v_pre_sub numeric:=0;
  v_pre_gst numeric:=0;
  v_pct numeric:=coalesce(p_value_added_pct,0);

  v_discount numeric;
  v_lines jsonb := '[]'::jsonb;
  v_ln jsonb;

  v_gross_rate numeric;
  v_final_rate numeric;
  v_qty integer;

  v_result jsonb;
  v_pid uuid;

  v_sub numeric;
  v_taxable numeric;
  v_gst numeric;
  v_raw numeric;
  v_grand numeric;
  v_round numeric;

begin

  perform public.rr_fg_assert_user_v787();
  if v_pct < -100 or v_pct::text in ('NaN','Infinity','-Infinity') then raise exception 'Value Added percent must be finite and at least -100.'; end if;

  if upper(coalesce(p_data_mode,'')) <> 'TEST' then
    raise exception
      'V816 sample wrapper locked to TEST until REAL approval.';
  end if;

  select *
  into v_customer
  from public.rr_customers
  where lower(customer_name)=lower(trim(p_customer_name))
    and coalesce(is_active,false)
  order by updated_at desc
  limit 1
  for update;

  if not found then
    raise exception 'Active Contact List customer required.';
  end if;

  if exists(select 1 from jsonb_array_elements(p_lines) x where x->>'stock_type'='TRADED') then
    if p_pi_id is not null then perform 1 from public.rr_fg_pi_v787 where id=p_pi_id and status='DRAFT' and data_mode='TEST' for update;end if;
    p_lines:=public.rr_rm_sale_allocate_test71(p_lines,p_pi_id);
  end if;

  v_discount :=
    coalesce(v_customer.allowed_discount_per_piece,0);

  if v_discount < 0 or v_discount > 10 then
    raise exception 'Invalid customer flat discount.';
  end if;

  if coalesce(p_freight_amount,0) < 0
     or coalesce(p_packing_other,0) < 0
     or coalesce(p_gst_pct,0) < 0
  then
    raise exception 'Invalid commercial charges.';
  end if;


  -- ----------------------------------------------------------
  -- APPLY SAME CONTACT-LIST FLAT DISCOUNT TO ALL BILL ITEMS
  -- ----------------------------------------------------------

  for v_ln in
    select *
    from jsonb_array_elements(p_lines)
  loop

    v_qty := (v_ln->>'qty')::integer;
    v_gross_rate := (v_ln->>'rate')::numeric;

    if v_qty <= 0 or v_gross_rate < 0 then
      raise exception 'Invalid Sales line.';
    end if;

    v_final_rate :=
      greatest(0,v_gross_rate-v_discount);

    v_pre_sub:=v_pre_sub+v_qty*v_final_rate;
    v_lines :=
      v_lines ||
      jsonb_build_array(
        jsonb_build_object(
          'lot_no',
            v_ln->>'lot_no',

          'short_item_name',
            coalesce(
              nullif(v_ln->>'short_item_name',''),
              v_ln->>'lot_no'
            ),

          'stock_type',
            v_ln->>'stock_type',

          'qty',
            v_qty,

          -- Canonical V787 receives FINAL RATE.
          'rate',
            v_final_rate,

          'gross_rate',
            v_gross_rate,

          'party_discount_per_piece',
            v_discount
        )
      );

  end loop;


  -- ----------------------------------------------------------
  -- CANONICAL PI/CPI + STOCK ENGINE
  -- Keep value-added = 0.
  -- Packing Other stays canonical.
  -- ----------------------------------------------------------

  v_pre_gst:=round((v_pre_sub+v_pre_sub*v_pct/100+coalesce(p_packing_other,0)+coalesce(p_freight_amount,0))*coalesce(p_gst_pct,0)/100,2);

  v_result :=
    public.rr_fg_save_pi_v787(
      p_pi_id,
      v_customer.customer_name,
      p_dispatch_details,
      v_lines,
      v_pct,
      coalesce(p_packing_other,0)+coalesce(p_freight_amount,0)+v_pre_gst,
      p_finalize,
      'TEST'
    );

  v_pid := (v_result->>'pi_id')::uuid;


  -- ----------------------------------------------------------
  -- STORE GROSS/DISCOUNT SNAPSHOT PER LINE
  -- ----------------------------------------------------------

  with src as (
    select
      x.value as ln,
      x.ordinality as rn
    from jsonb_array_elements(p_lines) with ordinality x
  ),
  dst as (
    select
      l.id,
      l.serial_no as rn
    from public.rr_fg_pi_lines_v787 l
    where l.pi_id=v_pid
  )
  update public.rr_fg_pi_lines_v787 l
  set
    gross_rate=(src.ln->>'rate')::numeric,
    original_rate=(src.ln->>'rate')::numeric,
    discount_amount=v_discount,
    party_discount_per_piece=v_discount,
    readymade_art_no_test71=src.ln->>'art_no',art_sale_key_test71=src.ln->>'art_sale_key'
  from src
  join dst on dst.rn=src.rn
  where l.id=dst.id;


  -- ----------------------------------------------------------
  -- COMMERCIAL TOTALS
  -- ----------------------------------------------------------

  select coalesce(sum(amount),0)
  into v_sub
  from public.rr_fg_pi_lines_v787
  where pi_id=v_pid;

  v_taxable :=
      v_sub
    + v_sub*v_pct/100
    + coalesce(p_packing_other,0)
    + coalesce(p_freight_amount,0);

  v_gst :=
    round(
      v_taxable *
      coalesce(p_gst_pct,0) / 100,
      2
    );

  v_raw :=
    v_taxable + v_gst;

  v_grand :=
    round(v_raw/10)*10;

  v_round :=
    v_grand-v_raw;


  update public.rr_fg_pi_v787
  set
    party_discount_per_piece=v_discount,
    value_added_pct=v_pct,
    freight_amount=coalesce(p_freight_amount,0),
    gst_pct=coalesce(p_gst_pct,0),
    gst_amount=v_gst,
    taxable_amount=v_taxable,

    -- Canonical packing_other preserved.
    packing_other=coalesce(p_packing_other,0),

    -- Final commercial values.
    sub_total=v_sub,
    round_off=v_round,
    grand_total=v_grand,

    buyer_snapshot =
      coalesce(buyer_snapshot,'{}'::jsonb)
      ||
      jsonb_build_object(
        'contact_customer_id',v_customer.id,
        'value_added_pct',v_pct,
      'value_added_amount',v_sub*v_pct/100,
      'customer_name',v_customer.customer_name,
        'mobile',v_customer.mobile,
        'gstin',v_customer.gstin,
        'address',v_customer.address,
        'city',v_customer.city,
        'state',v_customer.state,
        'party_flat_discount_per_piece',v_discount
      ),

    updated_at=now()

  where id=v_pid;


  -- The version captures the completed commercial header and discount snapshot.
  update public.rr_fg_pi_versions_v787 v
  set snapshot=jsonb_build_object('header',to_jsonb(p),'lines',
      (select jsonb_agg(to_jsonb(l) order by l.serial_no) from public.rr_fg_pi_lines_v787 l where l.pi_id=v_pid))
  from public.rr_fg_pi_v787 p
  where p.id=v_pid and v.pi_id=p.id and v.version_no=p.version_no;

  return
    v_result ||
    jsonb_build_object(
      'customer_name',v_customer.customer_name,
      'party_discount_per_piece',v_discount,
      'sub_total_after_discount',v_sub,
      'packing_other',coalesce(p_packing_other,0),
      'freight_amount',coalesce(p_freight_amount,0),
      'taxable_amount',v_taxable,
      'gst_pct',coalesce(p_gst_pct,0),
      'gst_amount',v_gst,
      'round_off',v_round,
      'grand_total',v_grand
    );

end;
$function$
;
CREATE OR REPLACE FUNCTION public.rr_sales_pi_detail_v500(p_pi_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.rr_fg_pi_v787%rowtype; lines_json jsonb;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 select * into p from public.rr_fg_pi_v787 where id=p_pi_id and data_mode='TEST';
 if p.id is null then raise exception 'Canonical PI not found.'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('lot_no',l.lot_no,'qty',l.qty,
 'rate',coalesce(l.gross_rate,l.original_rate),'discount',coalesce(l.party_discount_per_piece,l.discount_amount,0),
 'category',l.short_item_name,'stock_type',l.stock_type,'art_no',l.readymade_art_no_test71,'art_sale_key',l.art_sale_key_test71) order by l.serial_no,l.id),'[]'::jsonb)
 into lines_json from public.rr_fg_pi_lines_v787 l where l.pi_id=p.id;
 return jsonb_build_object('pi_id',p.id,'pi_no',p.pi_no,'customer_name',coalesce(p.buyer_snapshot->>'customer_name',p.buyer_snapshot->>'buyer_name'),
 'dispatch_details',p.dispatch_details,'requirement_id',p.market_requirement_id,'status',p.status,
 'value_added_pct',p.value_added_pct,'freight_amount',p.freight_amount,'packing_other',p.packing_other,'lines',lines_json);
end $function$
;
