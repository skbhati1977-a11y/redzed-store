BEGIN;
CREATE OR REPLACE FUNCTION public.rr_committee_payment_post_v824(p_scheme_id uuid, p_month_no integer, p_amount numeric, p_payment_mode text, p_organizer_reference text DEFAULT NULL::text, p_bank_reference text DEFAULT NULL::text, p_payment_date date DEFAULT CURRENT_DATE, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    s public.rr_committee_schemes_v820%rowtype;
    m public.rr_committee_months_v820%rowtype;

    v_mode text;
    v_already numeric;
    v_balance numeric;

    v_no text;
    v_id uuid;
begin

    if not public.rr_acct_can_view_v805() then
      raise exception 'Accounts permission required.';
    end if;

    select *
    into s
    from public.rr_committee_schemes_v820
    where id=p_scheme_id;

    if not found then
      raise exception 'Committee scheme not found.';
    end if;

    if s.data_mode<>'TEST' then
      raise exception 'V824 TEST only.';
    end if;

    if not coalesce(s.member_side_only,false) then
      raise exception 'Member-side Committee required.';
    end if;

    if coalesce(p_amount,0)<=0 then
      raise exception 'Payment amount must be positive.';
    end if;

    v_mode:=upper(trim(coalesce(p_payment_mode,'')));

    if v_mode not in ('CASH','BANK') then
      raise exception 'Payment mode must be CASH or BANK.';
    end if;

    if v_mode='BANK'
       and nullif(trim(p_bank_reference),'') is null then
      raise exception 'Bank reference required.';
    end if;

    select *
    into m
    from public.rr_committee_months_v820
    where scheme_id=p_scheme_id
      and month_no=p_month_no
    for update;

    if not found then
      raise exception 'Committee month not found.';
    end if;

    select coalesce(sum(amount),0)
    into v_already
    from public.rr_committee_payments_v824
    where month_id=m.id
      and status='POSTED';

    v_balance:=round(m.our_net_installment-v_already,2);

    if v_balance<=0 then
      raise exception 'Month already fully paid.';
    end if;

    if round(p_amount,2)>v_balance then
      raise exception
        'Payment exceeds outstanding ₹%',
        v_balance;
    end if;

    v_no :=
      'TCPAY'||
      nextval('public.rr_committee_test_payment_seq_v824');

    insert into public.rr_committee_payments_v824(
      scheme_id,
      month_id,
      payment_no,
      payment_date,
      payment_mode,
      amount,
      organizer_reference,
      bank_reference,
      remarks,
      status,
      data_mode
    )
    values(
      s.id,
      m.id,
      v_no,
      coalesce(p_payment_date,current_date),
      v_mode,
      round(p_amount,2),
      nullif(trim(p_organizer_reference),''),
      nullif(trim(p_bank_reference),''),
      nullif(trim(p_remarks),''),
      'POSTED',
      'TEST'
    )
    returning id into v_id;

    v_already:=round(v_already+p_amount,2);

    update public.rr_committee_months_v820
    set
      our_paid_amount=v_already,
      our_payment_status=
        case
          when v_already>=our_net_installment
            then 'PAID'
          else 'PENDING'
        end,
      updated_at=now()
    where id=m.id;

    -- Cash/Bank and contribution asset post atomically with the payment.
    perform public.rr_committee_payment_accounts_post_v825(v_id);
    return jsonb_build_object(
      'PASS',true,
      'payment_id',v_id,
      'payment_no',v_no,
      'scheme_code',s.scheme_code,
      'month_no',m.month_no,
      'payment_mode',v_mode,
      'amount',round(p_amount,2),
      'total_paid',v_already,
      'outstanding',
        round(greatest(m.our_net_installment-v_already,0),2),
      'status',
        case
          when v_already>=m.our_net_installment
            then 'PAID'
          else 'PARTIAL'
        end
    );
end;
$function$
;
COMMIT;

