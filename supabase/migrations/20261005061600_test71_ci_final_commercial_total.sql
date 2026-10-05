-- Final commercial total is computed by the existing stock/CI engine BEFORE CI status triggers post Accounts.
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
CREATE OR REPLACE FUNCTION public.rr_fg_save_pi_value_adjustment_test71(p_pi_id uuid, p_customer_name text, p_dispatch_details text, p_lines jsonb, p_party_discount numeric, p_value_added_pct numeric, p_freight_amount numeric DEFAULT 0, p_packing_other numeric DEFAULT 0, p_gst_pct numeric DEFAULT 0, p_finalize boolean DEFAULT false, p_data_mode text DEFAULT 'TEST'::text)
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

  v_res:=public.rr_fg_save_pi_commercial_test71(
    p_pi_id,p_customer_name,p_dispatch_details,p_lines,p_value_added_pct,
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
revoke all on function public.rr_fg_save_pi_commercial_test71(uuid,text,text,jsonb,numeric,numeric,numeric,numeric,boolean,text) from public,anon;
grant execute on function public.rr_fg_save_pi_commercial_test71(uuid,text,text,jsonb,numeric,numeric,numeric,numeric,boolean,text) to authenticated,service_role;

