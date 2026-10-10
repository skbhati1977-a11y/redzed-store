BEGIN;
CREATE OR REPLACE FUNCTION public.rr_acct_can_view_v805() RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO public AS $f$
DECLARE identity_json jsonb; effective_role text;
BEGIN
 IF auth.uid() IS NULL THEN RETURN false; END IF;
 IF current_setting('rr.trusted_account_bridge',true)='rci_reversal' THEN RETURN true;END IF;
 identity_json:=public.rr_upm_effective_identity_v200();
 effective_role:=upper(coalesce(identity_json->>'resolved_role',identity_json->>'role_code','WORKER'));
 IF effective_role NOT IN('OWNER','SUPER_ADMIN','ADMIN','ACCOUNT','ACCOUNTS') THEN RETURN false;END IF;
 RETURN public.rr_acct_can_view_base_v9762();
END;$f$;
REVOKE EXECUTE ON FUNCTION public.rr_acct_can_view_v805() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_acct_can_view_v805() TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_payroll_can_manage_v778() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO public AS $f$
 SELECT auth.uid() IS NOT NULL AND lower(coalesce(public.rr_upm_effective_identity_v200()->>'resolved_role',public.rr_upm_effective_identity_v200()->>'role_code','')) IN ('owner','super_admin','admin','account','accounts','manager','payroll','hr');
$f$;
REVOKE EXECUTE ON FUNCTION public.rr_payroll_can_manage_v778() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_payroll_can_manage_v778() TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_material_purchase_return_v806(p_purchase_id uuid, p_return_purchase_qty numeric, p_reason text, p_return_date date DEFAULT CURRENT_DATE, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_p jsonb;

  v_material_id uuid;
  v_supplier uuid;

  v_mode text;
  v_bill_no text;
  v_bill_date date;

  v_purchase_qty numeric;
  v_stock_qty numeric;
  v_return_qty numeric;
  v_return_stock_qty numeric;

  v_prior_qty numeric;
  v_remaining_qty numeric;

  v_current_stock numeric;

  v_rate numeric;
  v_base_value numeric;
  v_original_gst numeric;
  v_gst_return numeric;
  v_total_supplier_debit numeric;

  v_return_id uuid;

  v_purchase_return_ledger uuid;
  v_gst_input_ledger uuid;

  v_account jsonb;
  v_account_tx uuid;

  v_type text;
begin
  if not public.rr_is_owner_or_admin() then
    raise exception 'Owner/Admin permission required.';
  end if;

  if coalesce(p_return_purchase_qty,0)<=0 then
    raise exception 'Return Qty must be greater than zero.';
  end if;

  if nullif(trim(coalesce(p_reason,'')),'') is null then
    raise exception 'Purchase Return reason required.';
  end if;

  select to_jsonb(p)
  into v_p
  from public.rr_material_purchases_v805 p
  where p.id=p_purchase_id
  for update;

  if v_p is null then
    raise exception 'Generic Material purchase not found.';
  end if;

  v_material_id:=(v_p->>'material_id')::uuid;

  if v_material_id is null then
    raise exception 'Material ID missing on purchase.';
  end if;

  select mt.type_code
  into v_type
  from public.rr_material_master_v805 m
  join public.rr_material_types_v805 mt
    on mt.id=m.material_type_id
  where m.id=v_material_id;

  if v_type in(
    'REGULAR_CLOTH',
    'MATCHING_CLOTH',
    'STICKER',
    'METAL_ID'
  ) then
    raise exception
      '% Purchase Return must use its dedicated module.',
      replace(v_type,'_',' ');
  end if;

  v_mode:=upper(
    coalesce(
      nullif(v_p->>'data_mode',''),
      'TEST'
    )
  );

  perform public.rr_app_data_mode_assert_v786(v_mode);

  v_supplier:=
    nullif(v_p->>'supplier_ledger_id','')::uuid;

  if v_supplier is null then
    raise exception 'Supplier Ledger missing on purchase.';
  end if;

  v_purchase_qty:=coalesce(
    nullif(v_p->>'purchase_qty','')::numeric,
    nullif(v_p->>'qty','')::numeric,
    0
  );

  v_stock_qty:=coalesce(
    nullif(v_p->>'stock_qty','')::numeric,
    nullif(v_p->>'base_qty','')::numeric,
    v_purchase_qty
  );

  if v_purchase_qty<=0 or v_stock_qty<=0 then
    raise exception 'Original purchase quantity conversion missing.';
  end if;

  v_return_qty:=round(p_return_purchase_qty,6);

  select coalesce(sum(return_qty),0)
  into v_prior_qty
  from public.rr_purchase_returns_v806
  where source_module='GENERIC_MATERIAL'
    and source_purchase_id=p_purchase_id
    and status='POSTED';

  v_remaining_qty:=round(v_purchase_qty-v_prior_qty,6);

  if v_return_qty>v_remaining_qty then
    raise exception
      'Return Qty % exceeds remaining Purchase Qty %.',
      v_return_qty,v_remaining_qty;
  end if;

  v_return_stock_qty:=
    round(
      v_return_qty*(v_stock_qty/v_purchase_qty),
      6
    );

  select current_balance_qty
  into v_current_stock
  from public.rr_material_stock_effective_v806
  where material_id=v_material_id
    and data_mode=v_mode;

  if v_return_stock_qty>coalesce(v_current_stock,0) then
    raise exception
      'Return Stock Qty % exceeds available stock %.',
      v_return_stock_qty,v_current_stock;
  end if;

  v_rate:=coalesce(
    nullif(v_p->>'taxable_value','')::numeric / nullif(v_purchase_qty,0),
    nullif(v_p->>'rate_per_purchase_unit','')::numeric,
    nullif(v_p->>'effective_rate','')::numeric,
    nullif(v_p->>'rate','')::numeric
  );
  if v_rate is null or v_rate<=0 then raise exception 'Frozen purchase rate missing or invalid.'; end if;

  v_base_value:=round(v_return_qty*v_rate,2);

  v_original_gst:=coalesce(
    nullif(v_p->>'gst_amount','')::numeric,
    0
  );

  v_gst_return:=
    case
      when v_purchase_qty>0
      then round(
        v_original_gst*(v_return_qty/v_purchase_qty),
        2
      )
      else 0
    end;

  v_total_supplier_debit:=
    round(v_base_value+v_gst_return,2);

  v_bill_no:=v_p->>'bill_no';

  begin
    v_bill_date:=(v_p->>'bill_date')::date;
  exception when others then
    v_bill_date:=null;
  end;

  insert into public.rr_purchase_returns_v806(
    source_module,
    source_purchase_id,
    return_qty,
    rate_snapshot,
    return_value,
    supplier_ledger_id,
    bill_no,
    return_date,
    reason,
    remarks,
    data_mode,
    status,
    source_before,
    source_after,
    created_by
  )
  values(
    'GENERIC_MATERIAL',
    p_purchase_id,
    v_return_qty,
    v_rate,
    v_base_value,
    v_supplier,
    v_bill_no,
    coalesce(p_return_date,current_date),
    trim(p_reason),
    nullif(trim(p_remarks),''),
    v_mode,
    'POSTED',

    jsonb_build_object(
      'purchase_qty',v_purchase_qty,
      'prior_return_purchase_qty',v_prior_qty,
      'effective_stock_before',v_current_stock
    ),

    jsonb_build_object(
      'stock_return_qty',v_return_stock_qty,
      'gst_return',v_gst_return,
      'supplier_debit',v_total_supplier_debit,
      'effective_stock_after',
        round(v_current_stock-v_return_stock_qty,6)
    ),

    auth.uid()
  )
  returning id into v_return_id;


  -- ==========================================================
  -- ACCOUNTING
  -- Supplier DR = Base Return + GST reversal
  -- Purchase Return CR = Base Return
  -- GST Input CR = proportional GST return
  -- ==========================================================

  v_purchase_return_ledger:=
    public.rr_account_ledger_by_code_v806('PUR_RETURN');

  if v_gst_return>0 then
    v_gst_input_ledger:=
      public.rr_account_ledger_by_code_v806('TAX_GST_INPUT');
  end if;

  perform public.rr_source_data_mode_tag_v806(
    'GENERIC_MATERIAL_PURCHASE_RETURN',
    v_return_id::text,
    v_mode
  );

  v_account:=
    public.rr_accounts_mirror_post_v806(
      'PURCHASE_RETURN',
      v_total_supplier_debit,

      case
        when v_gst_return>0 then
          jsonb_build_array(

            jsonb_build_object(
              'ledger_id',v_supplier,
              'dr',v_total_supplier_debit,
              'cr',0,
              'narration','Generic Material Purchase Return'
            ),

            jsonb_build_object(
              'ledger_id',v_purchase_return_ledger,
              'dr',0,
              'cr',v_base_value,
              'narration','Purchase Return'
            ),

            jsonb_build_object(
              'ledger_id',v_gst_input_ledger,
              'dr',0,
              'cr',v_gst_return,
              'narration','GST Input Reversal'
            )
          )

        else
          jsonb_build_array(

            jsonb_build_object(
              'ledger_id',v_supplier,
              'dr',v_base_value,
              'cr',0,
              'narration','Generic Material Purchase Return'
            ),

            jsonb_build_object(
              'ledger_id',v_purchase_return_ledger,
              'dr',0,
              'cr',v_base_value,
              'narration','Purchase Return'
            )
          )
      end,

      'GENERIC_MATERIAL_PURCHASE_RETURN',
      v_return_id::text,
      v_supplier,
      v_bill_no,
      coalesce(p_return_date,v_bill_date,current_date),
      trim(p_reason),
      v_mode
    );

  v_account_tx:=(v_account->>'transaction_id')::uuid;

  update public.rr_purchase_returns_v806
  set account_transaction_id=v_account_tx
  where id=v_return_id;

  perform public.rr_material_reorder_check_v805_2(
    v_material_id,
    v_mode,
    'PURCHASE_RETURN',
    v_return_id::text
  );

  return jsonb_build_object(
    'ok',true,
    'purchase_return_id',v_return_id,
    'material_id',v_material_id,

    'return_purchase_qty',v_return_qty,
    'return_stock_qty',v_return_stock_qty,

    'base_return_value',v_base_value,
    'gst_return',v_gst_return,
    'supplier_debit',v_total_supplier_debit,

    'return_type',
      case
        when round(v_prior_qty+v_return_qty,6)
             >=round(v_purchase_qty,6)
        then 'FULL_RETURN'
        else 'PARTIAL_RETURN'
      end,

    'stock_before',v_current_stock,
    'stock_after',
      round(v_current_stock-v_return_stock_qty,6),

    'account_transaction_id',v_account_tx
  );
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_committee_payment_reverse_v824(p_payment_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    p public.rr_committee_payments_v824%rowtype;
    m public.rr_committee_months_v820%rowtype;
    v_paid numeric;
begin

    if not public.rr_acct_can_view_v805() then
      raise exception 'Accounts permission required.';
    end if;

    if nullif(trim(p_reason),'') is null then
      raise exception 'Reversal reason required.';
    end if;

    select *
    into p
    from public.rr_committee_payments_v824
    where id=p_payment_id
    for update;

    if not found then
      raise exception 'Payment not found.';
    end if;

    if p.data_mode<>'TEST' then
      raise exception 'V824 TEST only.';
    end if;

    if p.status='REVERSED' then
      raise exception 'Payment already reversed.';
    end if;

    -- Reverse the linked journal in the same transaction as the operational payment.
    if p.accounts_transaction_id is not null then
      perform public.rr_accounts_link_source_v806(
        'COMMITTEE_MEMBER_V825_INSTALLMENT',p.id::text,p.accounts_transaction_id,p.data_mode);
      perform public.rr_accounts_reverse_source_mirror_v806(
        'COMMITTEE_MEMBER_V825_INSTALLMENT',p.id::text,p.data_mode,trim(p_reason));
    end if;

    update public.rr_committee_payments_v824
    set
      status='REVERSED',
      reversed_at=now(),
      reversed_by=auth.uid(),
      reversal_reason=trim(p_reason),
      updated_at=now(),
      updated_by=auth.uid()
    where id=p.id;

    select *
    into m
    from public.rr_committee_months_v820
    where id=p.month_id
    for update;

    select coalesce(sum(amount),0)
    into v_paid
    from public.rr_committee_payments_v824
    where month_id=p.month_id
      and status='POSTED';

    update public.rr_committee_months_v820
    set
      our_paid_amount=round(v_paid,2),
      our_payment_status=
        case
          when v_paid>=our_net_installment
            then 'PAID'
          else 'PENDING'
        end,
      updated_at=now()
    where id=m.id;

    return jsonb_build_object(
      'PASS',true,
      'payment_no',p.payment_no,
      'month_no',m.month_no,
      'reversed_amount',p.amount,
      'remaining_paid',round(v_paid,2),
      'outstanding',
        round(greatest(m.our_net_installment-v_paid,0),2),
      'status','REVERSED'
    );
end;
$function$
;
COMMIT;

