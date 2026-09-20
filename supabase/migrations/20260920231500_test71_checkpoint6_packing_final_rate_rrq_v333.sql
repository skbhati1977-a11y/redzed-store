-- TEST71 Checkpoint 6 · canonical Packing final-rate/RRQ authority, privacy and idempotency.
-- Keeps the existing V9340 -> V312 -> V309/V9300 engine.  V333 only repairs its
-- role projection, retry semantics and direct-table/function exposure.

begin;

create or replace function public.rr_pack_rate_context_public_v333(
  p_lot_no text,
  p_data_mode text default 'TEST'
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_identity jsonb:=public.rr_upm_effective_identity_v200();
  v_role text;
  v_full jsonb;
begin
  v_role:=upper(coalesce(v_identity->>'role_code',v_identity->>'resolved_role',''));
  v_full:=public.rr_pack_rate_context_universal_v9405(p_lot_no,p_data_mode);

  if v_role in ('OWNER','SUPER_ADMIN') then
    return v_full||jsonb_build_object('visibility','SUPER_ADMIN_PRIVATE');
  end if;

  if v_role in ('ADMIN','MANAGER','SALES','SALESMAN') then
    return jsonb_build_object(
      'ok',coalesce((v_full->>'ok')::boolean,false),
      'costing_complete',coalesce((v_full->>'costing_complete')::boolean,false),
      'path',v_full->>'path',
      'calculated_sale_rate',v_full->'calculated_sale_rate',
      'source_rate',v_full->'source_rate',
      'approval_rounding',v_full->>'approval_rounding',
      'visibility',case when v_role in ('SALES','SALESMAN') then 'SALES_RATE' else 'ADMIN_RATE' end
    );
  end if;

  return jsonb_build_object(
    'ok',coalesce((v_full->>'ok')::boolean,false),
    'costing_complete',coalesce((v_full->>'costing_complete')::boolean,false),
    'path',v_full->>'path',
    'visibility','PACKING_STATUS_ONLY'
  );
end $$;

create or replace function public.rr_pack_rate_status_v9340(
  p_lot_no text,
  p_data_mode text default 'TEST'
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  r record;
  v_identity jsonb:=public.rr_upm_effective_identity_v200();
  v_role text;
  v_art text;
  v_base jsonb;
begin
  perform public.rr_fg_assert_user_v787();
  v_role:=upper(coalesce(v_identity->>'role_code',v_identity->>'resolved_role',''));

  select * into r
  from public.rr_pack_rate_approval_v9340
  where data_mode=upper(coalesce(p_data_mode,'TEST')) and lot_no=trim(p_lot_no);

  if not found then
    return jsonb_build_object(
      'lot_no',trim(p_lot_no),'status','NOT_REQUESTED','approved',false,
      'visibility',case
        when v_role in ('OWNER','SUPER_ADMIN') then 'SUPER_ADMIN_PRIVATE'
        when v_role in ('ADMIN','MANAGER') then 'ADMIN_RATE'
        when v_role in ('SALES','SALESMAN') then 'SALES_RATE'
        else 'PACKING_STATUS_ONLY'
      end,
      'next_action','COMPLETE_PACKING_AND_REQUEST_RATE'
    );
  end if;

  if r.status='APPROVED' then v_art:=public.rr_pack_art_code_v9340(r.final_rate); end if;
  v_base:=jsonb_build_object(
    'lot_no',r.lot_no,
    'status',r.status,
    'approved',r.status='APPROVED',
    'requested_at',r.requested_at,
    'approved_at',r.approved_at,
    'next_action',case when r.status='APPROVED' then 'FINALIZE_PACKING' else 'WAIT_FOR_RATE_APPROVAL' end
  );

  if v_role in ('OWNER','SUPER_ADMIN') then
    return v_base||jsonb_build_object(
      'visibility','SUPER_ADMIN_PRIVATE','art_code',v_art,
      'source_rate',r.source_rate,'suggested_rate',r.suggested_rate,
      'sales_suggested_rate',r.sales_suggested_rate,
      'admin_suggested_rate',r.admin_suggested_rate,
      'final_rate',r.final_rate,'qty',r.qty_snapshot,
      'reserve_delta_per_pc',case when r.status='APPROVED' then r.reserve_delta_per_pc end,
      'reserve_quota_impact',case when r.status='APPROVED' then r.reserve_quota_impact end,
      'suggested_at',r.suggested_at
    );
  elsif v_role in ('ADMIN','MANAGER') then
    return v_base||jsonb_build_object(
      'visibility','ADMIN_RATE','sale_rate',r.source_rate,'source_rate',r.source_rate,
      'sales_suggested_rate',r.sales_suggested_rate,
      'admin_suggested_rate',r.admin_suggested_rate,
      'final_rate',case when r.status='APPROVED' then r.final_rate end,
      'rrq_status',case when r.status='APPROVED' then 'MAPPED' else 'PENDING' end
    );
  elsif v_role in ('SALES','SALESMAN') then
    return v_base||jsonb_build_object(
      'visibility','SALES_RATE','sale_rate',r.source_rate,'source_rate',r.source_rate,
      'sales_suggested_rate',r.sales_suggested_rate,
      'final_rate',case when r.status='APPROVED' then r.final_rate end,
      'rrq_status',case when r.status='APPROVED' then 'MAPPED' else 'PENDING' end
    );
  end if;

  return v_base||jsonb_build_object('visibility','PACKING_STATUS_ONLY');
end $$;

create or replace function public.rr_pack_rate_suggest_v9340(
  p_lot_no text,
  p_suggested_rate numeric,
  p_data_mode text default 'TEST'
) returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_identity jsonb:=public.rr_upm_effective_identity_v200();
  v_role text;
  v_kind text;
begin
  v_role:=upper(coalesce(v_identity->>'role_code',v_identity->>'resolved_role',''));
  if v_role not in ('ADMIN','MANAGER','SALES','SALESMAN') then
    raise exception 'Sales/Admin/Manager rate suggestion access required';
  end if;
  if p_suggested_rate is null or p_suggested_rate<=0 or p_suggested_rate<>round(p_suggested_rate,0) then
    raise exception 'Suggested rate must be whole rupee';
  end if;
  v_kind:=case when v_role in ('SALES','SALESMAN') then 'SALES' else 'ADMIN' end;

  update public.rr_pack_rate_approval_v9340 set
    sales_suggested_rate=case when v_kind='SALES' then p_suggested_rate else sales_suggested_rate end,
    sales_suggested_by=case when v_kind='SALES' then auth.uid() else sales_suggested_by end,
    sales_suggested_at=case when v_kind='SALES' then now() else sales_suggested_at end,
    admin_suggested_rate=case when v_kind='ADMIN' then p_suggested_rate else admin_suggested_rate end,
    admin_suggested_by=case when v_kind='ADMIN' then auth.uid() else admin_suggested_by end,
    admin_suggested_at=case when v_kind='ADMIN' then now() else admin_suggested_at end,
    suggested_rate=p_suggested_rate,suggested_by=auth.uid(),suggested_at=now(),status='SUGGESTED',updated_at=now()
  where data_mode=upper(coalesce(p_data_mode,'TEST')) and lot_no=trim(p_lot_no) and status<>'APPROVED';
  if not found then raise exception 'Rate request not found or already approved'; end if;

  return jsonb_build_object(
    'ok',true,'suggestion_type',v_kind,'suggested_rate',p_suggested_rate,
    'performed_by',auth.uid(),'on_behalf_worker_id',v_identity->>'worker_id'
  );
end $$;

create or replace function public.rrq_apply_packing_rate_v9300(
  p_lot_no text,
  p_admin_final_rate numeric,
  p_data_mode text default 'TEST',
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_role text;
  v_mode text:=upper(coalesce(p_data_mode,'TEST'));
  v_ctx jsonb;
  v_base numeric;
  v_qty numeric;
  v_old numeric;
  v_delta_pc numeric;
  v_quota_delta numeric;
  v_balance numeric;
  v_canonical text;
  v_id uuid;
  v_ready boolean;
begin
  v_role:=lower(coalesce(public.rr_current_role(),''));
  if v_role not in ('owner','admin','super_admin') then
    raise exception 'Only Admin/Owner/Super Admin can decide RRQ sale rate.';
  end if;
  if p_admin_final_rate is null or p_admin_final_rate<0 or p_admin_final_rate<>round(p_admin_final_rate,0) then
    raise exception 'RRQ final sale rate must be a whole rupee.';
  end if;

  v_ctx:=public.rr_pack_rate_context_universal_v9405(trim(p_lot_no),v_mode);
  v_canonical:=nullif(v_ctx->>'canonical_lot_id','');
  v_base:=round(coalesce((v_ctx->>'source_rate')::numeric,0),0);
  v_qty:=coalesce((v_ctx->>'qty')::numeric,0);
  if coalesce((v_ctx->>'ok')::boolean,false) is not true or v_base<=0 or v_qty<=0 then
    raise exception 'Final costing or lot quantity missing.';
  end if;

  select id,final_sale_rate,dispatch_ready into v_id,v_old,v_ready
  from public.rrq_lot_rates_v9300
  where data_mode=v_mode and lot_no=trim(p_lot_no)
  for update;
  if found and v_ready and v_old=p_admin_final_rate then
    select balance into v_balance from public.rrq_balance_v9300 where data_mode=v_mode;
    return jsonb_build_object(
      'lot_no',trim(p_lot_no),'base_sale_rate',v_base,'final_sale_rate',p_admin_final_rate,
      'rrq_adjustment_per_pc',p_admin_final_rate-v_base,'quota_delta',0,
      'rrq_balance',coalesce(v_balance,0),'dispatch_ready',true,
      'mapping_path',v_ctx->>'path','duplicate_blocked',true
    );
  end if;

  v_old:=coalesce(v_old,v_base);
  v_delta_pc:=p_admin_final_rate-v_old;
  v_quota_delta:=v_delta_pc*v_qty;
  insert into public.rrq_balance_v9300(data_mode,balance) values(v_mode,0) on conflict do nothing;
  update public.rrq_balance_v9300 set balance=balance+v_quota_delta,updated_at=now()
  where data_mode=v_mode returning balance into v_balance;
  insert into public.rrq_lot_rates_v9300(
    data_mode,lot_no,canonical_lot_id,qty_snapshot,base_sale_rate,rrq_adjustment_per_pc,
    final_sale_rate,dispatch_ready,decided_by,decided_at,updated_at
  ) values(
    v_mode,trim(p_lot_no),v_canonical,v_qty,v_base,p_admin_final_rate-v_base,
    p_admin_final_rate,true,auth.uid(),now(),now()
  ) on conflict(data_mode,lot_no) do update set
    canonical_lot_id=coalesce(excluded.canonical_lot_id,public.rrq_lot_rates_v9300.canonical_lot_id),
    qty_snapshot=excluded.qty_snapshot,base_sale_rate=excluded.base_sale_rate,
    rrq_adjustment_per_pc=excluded.rrq_adjustment_per_pc,final_sale_rate=excluded.final_sale_rate,
    dispatch_ready=true,decided_by=auth.uid(),decided_at=now(),updated_at=now();
  insert into public.rrq_rate_ledger_v9300(
    data_mode,lot_no,event_type,qty,previous_rate,new_rate,delta_per_pc,quota_delta,balance_after,reason
  ) values(
    v_mode,trim(p_lot_no),'PACKING_ADMIN',v_qty,v_old,p_admin_final_rate,
    v_delta_pc,v_quota_delta,v_balance,coalesce(p_reason,'Admin RRQ decision')
  );
  update public.rr_fg_products_v787 set sale_rate=p_admin_final_rate where lot_no=trim(p_lot_no);
  return jsonb_build_object(
    'lot_no',trim(p_lot_no),'base_sale_rate',v_base,'final_sale_rate',p_admin_final_rate,
    'rrq_adjustment_per_pc',p_admin_final_rate-v_base,'quota_delta',v_quota_delta,
    'rrq_balance',v_balance,'dispatch_ready',true,'mapping_path',v_ctx->>'path',
    'duplicate_blocked',false
  );
end $$;

create or replace function public.rrq_apply_packing_rate_v309(
  p_lot_no text,
  p_admin_final_rate numeric,
  p_data_mode text default 'TEST',
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_role text;
  v_mode text:=upper(coalesce(p_data_mode,'TEST'));
  v_ctx jsonb;
  v_base numeric;
  v_qty numeric;
  v_old numeric;
  v_delta numeric;
  v_quota_delta numeric;
  v_balance numeric;
  v_canonical text;
  v_id uuid;
  v_ready boolean;
begin
  v_role:=lower(coalesce(public.rr_current_role(),''));
  if v_role not in ('owner','admin','super_admin') then
    raise exception 'Only Admin/Owner/Super Admin can decide RRQ sale rate.';
  end if;
  if p_admin_final_rate is null or p_admin_final_rate<0 or p_admin_final_rate<>round(p_admin_final_rate,0) then
    raise exception 'RRQ final sale rate must be a whole rupee.';
  end if;

  v_ctx:=public.rr_pack_rate_context_v309(trim(p_lot_no),v_mode);
  v_canonical:=nullif(v_ctx->>'canonical_lot_id','');
  v_base:=round(coalesce((v_ctx->>'source_rate')::numeric,0),0);
  v_qty:=coalesce((v_ctx->>'qty')::numeric,0);
  if coalesce((v_ctx->>'ok')::boolean,false) is not true or v_base<=0 or v_qty<=0 then
    raise exception 'Final costing or lot quantity missing.';
  end if;

  select id,final_sale_rate,dispatch_ready into v_id,v_old,v_ready
  from public.rrq_lot_rates_v9300
  where data_mode=v_mode and lot_no=trim(p_lot_no)
  for update;
  if found and v_ready and v_old=p_admin_final_rate then
    select balance into v_balance from public.rrq_balance_v9300 where data_mode=v_mode;
    return jsonb_build_object(
      'lot_no',trim(p_lot_no),'base_sale_rate',v_base,'final_sale_rate',p_admin_final_rate,
      'rrq_adjustment_per_pc',p_admin_final_rate-v_base,'quota_delta',0,
      'rrq_balance',coalesce(v_balance,0),'dispatch_ready',true,
      'mapping_path',v_ctx->>'path','costing_authority','V308','duplicate_blocked',true
    );
  end if;

  v_old:=coalesce(v_old,v_base);
  v_delta:=p_admin_final_rate-v_old;
  v_quota_delta:=v_delta*v_qty;
  insert into public.rrq_balance_v9300(data_mode,balance) values(v_mode,0) on conflict do nothing;
  update public.rrq_balance_v9300 set balance=balance+v_quota_delta,updated_at=now()
  where data_mode=v_mode returning balance into v_balance;
  insert into public.rrq_lot_rates_v9300(
    data_mode,lot_no,canonical_lot_id,qty_snapshot,base_sale_rate,rrq_adjustment_per_pc,
    final_sale_rate,dispatch_ready,decided_by,decided_at,updated_at
  ) values(
    v_mode,trim(p_lot_no),v_canonical,v_qty,v_base,p_admin_final_rate-v_base,
    p_admin_final_rate,true,auth.uid(),now(),now()
  ) on conflict(data_mode,lot_no) do update set
    canonical_lot_id=coalesce(excluded.canonical_lot_id,public.rrq_lot_rates_v9300.canonical_lot_id),
    qty_snapshot=excluded.qty_snapshot,base_sale_rate=excluded.base_sale_rate,
    rrq_adjustment_per_pc=excluded.rrq_adjustment_per_pc,final_sale_rate=excluded.final_sale_rate,
    dispatch_ready=true,decided_by=auth.uid(),decided_at=now(),updated_at=now();
  insert into public.rrq_rate_ledger_v9300(
    data_mode,lot_no,event_type,qty,previous_rate,new_rate,delta_per_pc,quota_delta,balance_after,reason
  ) values(
    v_mode,trim(p_lot_no),'PACKING_ADMIN_V309',v_qty,v_old,p_admin_final_rate,
    v_delta,v_quota_delta,v_balance,coalesce(p_reason,'Admin RRQ decision · V308 final costing authority')
  );
  update public.rr_fg_products_v787 set sale_rate=p_admin_final_rate where lot_no=trim(p_lot_no);
  return jsonb_build_object(
    'lot_no',trim(p_lot_no),'base_sale_rate',v_base,'final_sale_rate',p_admin_final_rate,
    'rrq_adjustment_per_pc',p_admin_final_rate-v_base,'quota_delta',v_quota_delta,
    'rrq_balance',v_balance,'dispatch_ready',true,'mapping_path',v_ctx->>'path',
    'costing_authority','V308','duplicate_blocked',false
  );
end $$;

create or replace function public.rr_pack_rate_approve_v9340(
  p_lot_no text,
  p_final_rate numeric,
  p_data_mode text default 'TEST'
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_identity jsonb:=public.rr_upm_effective_identity_v200();
  v_role text;
  r record;
  v_apply jsonb;
  v_delta numeric;
  v_impact numeric;
  v_ctx jsonb;
begin
  v_role:=upper(coalesce(v_identity->>'role_code',v_identity->>'resolved_role',''));
  if v_role not in ('OWNER','SUPER_ADMIN') then
    raise exception 'Effective Super Admin approval required';
  end if;
  if p_final_rate is null or p_final_rate<=0 or p_final_rate<>round(p_final_rate,0) then
    raise exception 'Final rate must be whole rupee';
  end if;

  select * into r
  from public.rr_pack_rate_approval_v9340
  where data_mode=upper(coalesce(p_data_mode,'TEST')) and lot_no=trim(p_lot_no)
  for update;
  if not found then raise exception 'Rate request not found'; end if;

  if r.status='APPROVED' then
    if r.final_rate=p_final_rate then
      return jsonb_build_object(
        'ok',true,'lot_no',r.lot_no,'final_rate',r.final_rate,
        'reserve_delta_per_pc',r.reserve_delta_per_pc,
        'reserve_quota_impact',r.reserve_quota_impact,
        'duplicate_blocked',true,'status','APPROVED'
      );
    end if;
    raise exception 'Final rate already approved at ₹%. Explicit reversal is required before a different rate.',r.final_rate;
  end if;

  v_ctx:=public.rr_pack_rate_context_universal_v9405(trim(p_lot_no),upper(coalesce(p_data_mode,'TEST')));
  if coalesce((v_ctx->>'costing_complete')::boolean,false) is not true then
    raise exception 'Material ya department actual costing incomplete';
  end if;

  v_apply:=public.rrq_apply_packing_rate_compat_v312(
    trim(p_lot_no),p_final_rate,upper(coalesce(p_data_mode,'TEST')),
    'Packing final rate approved from mirrored App/Real Chat review'
  );
  v_delta:=p_final_rate-round((v_ctx->>'source_rate')::numeric,0);
  v_impact:=v_delta*r.qty_snapshot;
  update public.rr_pack_rate_approval_v9340 set
    source_rate=round((v_ctx->>'source_rate')::numeric,0),final_rate=p_final_rate,
    reserve_delta_per_pc=v_delta,reserve_quota_impact=v_impact,status='APPROVED',
    approved_by=auth.uid(),approved_at=now(),updated_at=now()
  where id=r.id;
  return jsonb_build_object(
    'ok',true,'lot_no',r.lot_no,'mapped_cost_per_pc',v_ctx->'base_cost_per_pc',
    'mapped_sale_suggestion',v_ctx->'source_rate','final_rate',p_final_rate,
    'art_code',public.rr_pack_art_code_v9340(p_final_rate),
    'reserve_delta_per_pc',v_delta,'reserve_quota_impact',v_impact,
    'rrq',v_apply,'costing_path',v_ctx->>'path','duplicate_blocked',false,'status','APPROVED'
  );
end $$;

-- A rollback-only, E2E-identity-gated proof against canonical Lot 2614.
-- It exercises the real V9340/V312 writer twice, then rolls every mutation back.
create or replace function public.rr_test_checkpoint6_rate_approval_v333()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_profile record;
  v_first jsonb;
  v_second jsonb;
  v_lot_before int;
  v_lot_during int;
  v_ledger_before int;
  v_ledger_during int;
  v_balance_before numeric;
  v_balance_during numeric;
  v_lot_after int;
  v_ledger_after int;
  v_balance_after numeric;
begin
  select role_code,full_name into v_profile
  from public.rr_user_profiles
  where auth_user_id=auth.uid() and is_active
  order by updated_at desc nulls last limit 1;
  if lower(coalesce(v_profile.role_code,''))<>'super_admin'
     or lower(coalesce(v_profile.full_name,'')) not like '%test%e2e%' then
    raise exception 'TEST71 E2E Super Admin session required';
  end if;
  if coalesce((public.rr_upm_effective_identity_v200()->>'on_behalf')::boolean,false) then
    raise exception 'Return Act As to signed-in TEST E2E Super Admin before running fixture';
  end if;

  select count(*) into v_lot_before from public.rrq_lot_rates_v9300 where data_mode='TEST' and lot_no='2614';
  select count(*) into v_ledger_before from public.rrq_rate_ledger_v9300 where data_mode='TEST' and lot_no='2614';
  select coalesce(balance,0) into v_balance_before from public.rrq_balance_v9300 where data_mode='TEST';
  v_balance_before:=coalesce(v_balance_before,0);

  begin
    v_first:=public.rr_pack_rate_approve_v9340('2614',75,'TEST');
    v_second:=public.rr_pack_rate_approve_v9340('2614',75,'TEST');
    select count(*) into v_lot_during from public.rrq_lot_rates_v9300 where data_mode='TEST' and lot_no='2614';
    select count(*) into v_ledger_during from public.rrq_rate_ledger_v9300 where data_mode='TEST' and lot_no='2614';
    select coalesce(balance,0) into v_balance_during from public.rrq_balance_v9300 where data_mode='TEST';
    raise exception '__TEST71_CP6_ROLLBACK__';
  exception when raise_exception then
    if sqlerrm<>'__TEST71_CP6_ROLLBACK__' then raise; end if;
  end;

  select count(*) into v_lot_after from public.rrq_lot_rates_v9300 where data_mode='TEST' and lot_no='2614';
  select count(*) into v_ledger_after from public.rrq_rate_ledger_v9300 where data_mode='TEST' and lot_no='2614';
  select coalesce(balance,0) into v_balance_after from public.rrq_balance_v9300 where data_mode='TEST';
  return jsonb_build_object(
    'lot_no','2614','final_rate',75,'first',v_first,'second',v_second,
    'lot_row_delta_during',v_lot_during-v_lot_before,
    'ledger_delta_during',v_ledger_during-v_ledger_before,
    'balance_delta_during',v_balance_during-v_balance_before,
    'rolled_back',v_lot_after=v_lot_before and v_ledger_after=v_ledger_before and v_balance_after=v_balance_before,
    'persisted',not (v_lot_after=v_lot_before and v_ledger_after=v_ledger_before and v_balance_after=v_balance_before)
  );
end $$;

alter table public.rr_pack_rate_approval_v9340 enable row level security;

revoke all on table public.rr_pack_rate_approval_v9340 from public,anon,authenticated;
revoke all on table public.rrq_balance_v9300 from public,anon,authenticated;
revoke all on table public.rrq_lot_rates_v9300 from public,anon,authenticated;
revoke all on table public.rrq_rate_ledger_v9300 from public,anon,authenticated;
grant select,insert,update,delete on table public.rr_pack_rate_approval_v9340 to service_role;
grant select,insert,update,delete on table public.rrq_balance_v9300 to service_role;
grant select,insert,update,delete on table public.rrq_lot_rates_v9300 to service_role;
grant select,insert,update,delete on table public.rrq_rate_ledger_v9300 to service_role;

revoke all on function public.rr_pack_rate_context_universal_v9405(text,text) from public,anon,authenticated;
revoke all on function public.rr_pack_rate_context_v309(text,text) from public,anon,authenticated;
revoke all on function public.rrq_apply_packing_rate_compat_v312(text,numeric,text,text) from public,anon,authenticated;
revoke all on function public.rrq_apply_packing_rate_v309(text,numeric,text,text) from public,anon,authenticated;
revoke all on function public.rrq_apply_packing_rate_v9300(text,numeric,text,text) from public,anon,authenticated;
grant execute on function public.rr_pack_rate_context_universal_v9405(text,text) to service_role;
grant execute on function public.rr_pack_rate_context_v309(text,text) to service_role;
grant execute on function public.rrq_apply_packing_rate_compat_v312(text,numeric,text,text) to service_role;
grant execute on function public.rrq_apply_packing_rate_v309(text,numeric,text,text) to service_role;
grant execute on function public.rrq_apply_packing_rate_v9300(text,numeric,text,text) to service_role;

revoke all on function public.rr_pack_rate_context_public_v333(text,text) from public,anon;
revoke all on function public.rr_pack_rate_status_v9340(text,text) from public,anon;
revoke all on function public.rr_pack_rate_suggest_v9340(text,numeric,text) from public,anon;
revoke all on function public.rr_pack_rate_approve_v9340(text,numeric,text) from public,anon;
revoke all on function public.rr_test_checkpoint6_rate_approval_v333() from public,anon;
grant execute on function public.rr_pack_rate_context_public_v333(text,text) to authenticated;
grant execute on function public.rr_pack_rate_status_v9340(text,text) to authenticated;
grant execute on function public.rr_pack_rate_suggest_v9340(text,numeric,text) to authenticated;
grant execute on function public.rr_pack_rate_approve_v9340(text,numeric,text) to authenticated;
grant execute on function public.rr_test_checkpoint6_rate_approval_v333() to authenticated;

commit;
