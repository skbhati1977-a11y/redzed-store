-- TEST71 V613: prove the canonical MC1 purchase -> reservation -> consumption
-- -> costing chain without leaving another confirmed E2E purchase behind.
-- The business writers stay unchanged. This helper is restricted to the
-- signed-in TEST E2E Super Admin and rolls its fixture subtransaction back.
begin;

create or replace function public.rr_test_mc1_e2e_invariants_v613()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $function$
declare
  v_profile record;
  v_fabric_before public.rr_mc1_fabrics%rowtype;
  v_fabric_during public.rr_mc1_fabrics%rowtype;
  v_fabric_after public.rr_mc1_fabrics%rowtype;
  v_account_before public.rr_mc1_account%rowtype;
  v_account_during public.rr_mc1_account%rowtype;
  v_account_after public.rr_mc1_account%rowtype;
  v_supplier record;
  v_key uuid:=gen_random_uuid();
  v_bill text:='TEST71-MC1-'||upper(substr(replace(v_key::text,'-',''),1,12));
  v_lot text;
  v_canonical_lot_id text;
  v_first jsonb;
  v_retry jsonb;
  v_reserve_first jsonb;
  v_reserve_retry jsonb;
  v_consume_first jsonb;
  v_consume_retry jsonb;
  v_open jsonb;
  v_working jsonb;
  v_close jsonb;
  v_costing jsonb;
  v_purchase_count integer:=0;
  v_purchase_in_count integer:=0;
  v_reservation_count integer:=0;
  v_consumption_count integer:=0;
  v_residue integer:=0;
begin
  select role_code,full_name into v_profile
  from public.rr_user_profiles
  where auth_user_id=auth.uid() and is_active
  order by updated_at desc nulls last
  limit 1;
  if upper(coalesce(v_profile.role_code,''))<>'SUPER_ADMIN'
     or lower(coalesce(v_profile.full_name,'')) not like '%test%e2e%' then
    raise exception 'TEST71 E2E Super Admin session required.' using errcode='42501';
  end if;
  if coalesce((public.rr_upm_effective_identity_v200()->>'on_behalf')::boolean,false) then
    raise exception 'Return Act As to signed-in TEST E2E Super Admin first.' using errcode='42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('TEST71_MC1_E2E_V613',613));

  select * into v_fabric_before
  from public.rr_mc1_fabrics
  where is_active and upper(fabric_name) like 'TEST E2E%'
  order by created_at
  limit 1
  for update;
  if v_fabric_before.id is null then
    raise exception 'Safe MC1 E2E fabric fixture missing.';
  end if;

  select * into v_account_before
  from public.rr_mc1_account
  where id=v_fabric_before.mc_account_id
  for update;

  select id supplier_ledger_id,ledger_name vendor_name into v_supplier
  from public.rr_ledgers_v805
  where ledger_kind='SUPPLIER' and is_active
    and upper(ledger_name) like 'TEST SUPPLIER E2E%'
  order by created_at
  limit 1;
  if v_supplier.supplier_ledger_id is null then
    raise exception 'Safe MC1 E2E supplier fixture missing.';
  end if;

  select 'rr_cutting_lots_v3:'||c.id::text,c.lot_no
    into v_canonical_lot_id,v_lot
  from public.rr_cutting_lots_v3 c
  where upper(coalesce(c.lot_no,'')) like 'E2E%'
    and upper(coalesce(c.notes,'')) like '%TEST%'
    and not exists(
      select 1 from public.rr_mc1_lot_matchings_v2 m
      where lower(trim(m.lot_no))=lower(trim(c.lot_no))
        and m.status in('RESERVED','POSTED')
    )
  order by c.created_at,c.id
  limit 1
  for update;
  if v_lot is null then
    raise exception 'Safe released TEST lot without Matching consumption is unavailable.';
  end if;

  begin
    v_first:=public.rr_confirm_mc_purchase_v504(
      v_key,v_fabric_before.id,v_fabric_before.fabric_name,
      v_supplier.supplier_ledger_id,v_supplier.vendor_name,v_bill,
      0.001,0.25,current_date,'TEST71 V613 rollback-only MC1 proof'
    );
    v_retry:=public.rr_confirm_mc_purchase_v504(
      v_key,v_fabric_before.id,v_fabric_before.fabric_name,
      v_supplier.supplier_ledger_id,v_supplier.vendor_name,v_bill,
      0.001,0.25,current_date,'TEST71 V613 rollback-only MC1 proof retry'
    );

    select count(*) into v_purchase_count
    from public.rr_mc1_purchases where idempotency_key=v_key;
    select count(*) into v_purchase_in_count
    from public.rr_mc1_ledger
    where entry_type='PURCHASE_IN'
      and reference_id=(v_first->>'purchase_id')::uuid
      and reversed_at is null;

    v_reserve_first:=public.rr_reserve_lot_matching_v2(
      v_fabric_before.id,v_lot,0.001,'TEST71_E2E',
      'TEST71 V613 rollback-only exact-run reservation'
    );
    v_reserve_retry:=public.rr_reserve_lot_matching_v2(
      v_fabric_before.id,v_lot,0.001,'TEST71_E2E',
      'TEST71 V613 rollback-only exact-run reservation retry'
    );
    select count(*) into v_reservation_count
    from public.rr_mc1_lot_matchings_v2
    where lower(trim(lot_no))=lower(trim(v_lot)) and status='RESERVED';

    v_consume_first:=public.rr_confirm_lot_matching_v2(v_lot,null);
    v_consume_retry:=public.rr_confirm_lot_matching_v2(v_lot,null);
    select count(*) into v_consumption_count
    from public.rr_mc1_ledger
    where entry_type='LOT_CONSUMPTION_OUT'
      and reference_id=(v_reserve_first->>'reservation_id')::uuid
      and reversed_at is null;

    v_open:=public.rr_mc1_real_chat_queue_v504('OPEN',v_bill);
    v_working:=public.rr_mc1_real_chat_queue_v504('WORKING',v_lot);
    v_close:=public.rr_mc1_real_chat_queue_v504('CLOSE',v_fabric_before.fabric_name);
    v_costing:=public.rr_upm_final_costing_v308(v_canonical_lot_id,'TEST');

    select * into v_fabric_during from public.rr_mc1_fabrics where id=v_fabric_before.id;
    select * into v_account_during from public.rr_mc1_account where id=v_account_before.id;

    if coalesce((v_first->>'duplicate_blocked')::boolean,true)
       or not coalesce((v_retry->>'duplicate_blocked')::boolean,false)
       or v_purchase_count<>1 or v_purchase_in_count<>1
       or (v_first->>'supplier_ledger_id')::uuid<>v_supplier.supplier_ledger_id
       or (v_reserve_first->>'reservation_id')::uuid<>(v_reserve_retry->>'reservation_id')::uuid
       or v_reservation_count<>1
       or coalesce((v_consume_first->>'duplicate_blocked')::boolean,true)
       or not coalesce((v_consume_retry->>'duplicate_blocked')::boolean,false)
       or v_consumption_count<>1
       or jsonb_array_length(coalesce(v_open->'cards','[]'::jsonb))<>1
       or (v_open->'cards'->0->>'purchase_id')::uuid<>(v_first->>'purchase_id')::uuid
       or jsonb_array_length(coalesce(v_working->'cards','[]'::jsonb))<>1
       or upper(v_working->'cards'->0->>'lot_no')<>upper(v_lot)
       or jsonb_array_length(coalesce(v_close->'cards','[]'::jsonb))<>1
       or coalesce((v_costing->'cloth'->>'matching_qty_kg')::numeric,0)<>0.001
       or coalesce((v_costing->'cloth'->>'matching_total')::numeric,0)<>coalesce((v_consume_first->>'total_cost')::numeric,0)
       or v_fabric_during.current_qty<>v_fabric_before.current_qty
       or v_account_during.current_qty<>v_account_before.current_qty
       or v_fabric_during.total_purchase_qty<>v_fabric_before.total_purchase_qty+0.001
       or v_fabric_during.total_consumption_qty<>v_fabric_before.total_consumption_qty+0.001 then
      raise exception 'V613 canonical MC1 invariant failed.';
    end if;

    raise exception using errcode='P6131',message='TEST71_MC1_E2E_ROLLBACK';
  exception when sqlstate 'P6131' then
    if sqlerrm<>'TEST71_MC1_E2E_ROLLBACK' then raise; end if;
  end;

  select * into v_fabric_after from public.rr_mc1_fabrics where id=v_fabric_before.id;
  select * into v_account_after from public.rr_mc1_account where id=v_account_before.id;
  select
    (select count(*) from public.rr_mc1_purchases where idempotency_key=v_key)
    +(select count(*) from public.rr_mc1_ledger where reference_id in(
        (v_first->>'purchase_id')::uuid,(v_reserve_first->>'reservation_id')::uuid
      ))
    +(select count(*) from public.rr_mc1_lot_matchings_v2
      where lower(trim(lot_no))=lower(trim(v_lot)) and status in('RESERVED','POSTED'))
    into v_residue;

  return jsonb_build_object(
    'fixture',jsonb_build_object(
      'idempotency_key',v_key,'bill_no',v_bill,'lot_no',v_lot,
      'canonical_lot_id',v_canonical_lot_id,'fabric_id',v_fabric_before.id,
      'fabric_name',v_fabric_before.fabric_name,'supplier_ledger_id',v_supplier.supplier_ledger_id
    ),
    'purchase',jsonb_build_object(
      'first',v_first,'retry',v_retry,'purchase_rows',v_purchase_count,
      'purchase_in_rows',v_purchase_in_count
    ),
    'consumption',jsonb_build_object(
      'reserve_first',v_reserve_first,'reserve_retry',v_reserve_retry,
      'confirm_first',v_consume_first,'confirm_retry',v_consume_retry,
      'reservation_rows',v_reservation_count,'consumption_rows',v_consumption_count
    ),
    'projection',jsonb_build_object('open',v_open,'working',v_working,'close',v_close),
    'costing',v_costing->'cloth',
    'rolled_back',v_residue=0
      and to_jsonb(v_fabric_after)=to_jsonb(v_fabric_before)
      and to_jsonb(v_account_after)=to_jsonb(v_account_before),
    'fixture_residue',v_residue
  );
end
$function$;

revoke all on function public.rr_test_mc1_e2e_invariants_v613() from public,anon;
grant execute on function public.rr_test_mc1_e2e_invariants_v613() to authenticated,service_role;

comment on function public.rr_test_mc1_e2e_invariants_v613() is
  'TEST71 E2E Super Admin-only rollback proof for one canonical MC1 purchase, PURCHASE_IN, reservation, consumption, costing and Real Chat projection; leaves zero fixture residue.';

notify pgrst,'reload schema';
commit;
