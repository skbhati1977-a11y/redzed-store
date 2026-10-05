-- TEST71: atomic party-wide discount approval; finalized bills retain their snapshots.
CREATE OR REPLACE FUNCTION public.rr_pi_actor_context_v9526() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare r text;
begin
 if auth.uid() is null then raise exception 'LOGIN REQUIRED'; end if;
 select lower(trim(coalesce(role_code,''))) into r from public.rr_user_profiles
 where auth_user_id=auth.uid() and is_active is true and upper(coalesce(access_status,'ACTIVE'))='ACTIVE'
 order by updated_at desc limit 1;
 if not found then raise exception 'ACTIVE STAFF REQUIRED'; end if;
 return jsonb_build_object('role',r,'superadmin',r in ('superadmin','super_admin','owner'));
end $function$;

CREATE OR REPLACE FUNCTION public.rr_market_set_customer_discount_v9423(p_customer_id uuid,p_discount numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare v_actor jsonb; v_old numeric; v_new numeric:=coalesce(p_discount,0);
begin
 v_actor:=public.rr_pi_actor_context_v9526();
 if not coalesce((v_actor->>'superadmin')::boolean,false) then raise exception 'SUPERADMIN ONLY'; end if;
 if v_new<0 or v_new>10 then raise exception 'Invalid customer flat discount.'; end if;
 select coalesce(allowed_discount_per_piece,0) into v_old from public.rr_customers where id=p_customer_id for update;
 if not found then raise exception 'CUSTOMER NOT FOUND'; end if;
 if v_new<>v_old then
 update public.rr_customers set allowed_discount_per_piece=v_new,updated_at=now() where id=p_customer_id;
 insert into public.rr_customer_discount_history_v9420(customer_id,discount_per_piece,effective_from,changed_by) values(p_customer_id,v_new,now(),auth.uid());
 end if;
 return jsonb_build_object('customer_id',p_customer_id,'old_discount',v_old,'discount_per_piece',v_new,'effective_from',now());
end $function$;

CREATE OR REPLACE FUNCTION public.rr_fg_save_pi_party_discount_v9557(p_pi_id uuid, p_customer_name text, p_dispatch_details text, p_lines jsonb, p_party_discount numeric, p_freight_amount numeric DEFAULT 0, p_packing_other numeric DEFAULT 0, p_gst_pct numeric DEFAULT 0, p_finalize boolean DEFAULT false, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_customer public.rr_customers%rowtype;
  v_role text;
  v_old numeric;
  v_new numeric;
  v_res jsonb;
  v_pid uuid;
begin
  perform public.rr_fg_assert_user_v787();

  select * into v_customer
  from public.rr_customers
  where lower(customer_name)=lower(trim(p_customer_name))
    and coalesce(is_active,false)
  order by updated_at desc
  limit 1
  for update;
  if not found then raise exception 'Active Contact List customer required.'; end if;

  select lower(trim(coalesce(role_code,''))) into v_role
  from public.rr_user_profiles
  where auth_user_id=auth.uid() and is_active is true and upper(coalesce(access_status,'ACTIVE'))='ACTIVE'
  order by updated_at desc limit 1;

  v_old:=coalesce(v_customer.allowed_discount_per_piece,0);
  v_new:=coalesce(p_party_discount,v_old);
  if v_new<0 or v_new>10 then raise exception 'Invalid customer flat discount.'; end if;

  if v_new<>v_old and coalesce(v_role,'') not in ('superadmin','super_admin','owner') then
    raise exception 'SUPERADMIN ONLY: party discount is view-only.';
  end if;

  if v_new<>v_old then
    update public.rr_customers
    set allowed_discount_per_piece=v_new,updated_at=now()
    where id=v_customer.id;
  end if;

  v_res:=public.rr_fg_save_pi_v816(
    p_pi_id,p_customer_name,p_dispatch_details,p_lines,
    coalesce(p_freight_amount,0),coalesce(p_packing_other,0),coalesce(p_gst_pct,0),
    p_finalize,p_data_mode
  );

  v_pid:=nullif(v_res->>'pi_id','')::uuid;

  if v_new<>v_old then
    insert into public.rr_customer_discount_history_v9420(
      customer_id,discount_per_piece,effective_from,changed_by,source_pi_id
    ) values(
      v_customer.id,v_new,now(),auth.uid(),v_pid
    );
  end if;

  return v_res || jsonb_build_object(
    'party_discount_per_piece',v_new,
    'previous_party_discount_per_piece',v_old,
    'discount_changed',v_new<>v_old,
    'discount_effective_pi_id',v_pid
  );
end $function$
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

            v_rate:=(v_trade->>'final_rate')::numeric;
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
                if (ln->>'gross_rate')::numeric is distinct from (v_trade->>'target_sale_rate')::numeric then
                    raise exception 'TRADED gross rate must match approved target sale rate.';
                end if;
                v_rate:=greatest(0,(v_trade->>'target_sale_rate')::numeric-v_party_discount);
                if v_rate<(v_trade->>'minimum_allowed_sale_rate')::numeric then
                    raise exception 'Party discount exceeds TRADED minimum sale rate.';
                end if;
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

CREATE OR REPLACE FUNCTION public.rr_fg_save_pi_v816(p_pi_id uuid, p_customer_name text, p_dispatch_details text, p_lines jsonb, p_freight_amount numeric DEFAULT 0, p_packing_other numeric DEFAULT 0, p_gst_pct numeric DEFAULT 0, p_finalize boolean DEFAULT false, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_customer public.rr_customers%rowtype;

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

  v_result :=
    public.rr_fg_save_pi_v787(
      p_pi_id,
      v_customer.customer_name,
      p_dispatch_details,
      v_lines,
      0,
      coalesce(p_packing_other,0),
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
    party_discount_per_piece=v_discount
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
