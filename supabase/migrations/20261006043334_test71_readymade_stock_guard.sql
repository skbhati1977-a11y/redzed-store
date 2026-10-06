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
