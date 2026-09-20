-- TEST71 Checkpoint 7 fixture-only repair: correct deterministic ordering.
-- The failed proof aborted before any business mutation; this only recreates
-- the rollback-only E2E helper and leaves the canonical engine unchanged.

begin;

create or replace function public.rr_test_checkpoint7_despatch_receive_v335()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_profile record;
  v_line uuid;
  v_partial_box record;
  v_partial_before int;
  v_full_before int;
  v_ready_before int;
  v_despatch_before int;
  v_ledger_before int;
  v_partial jsonb;
  v_partial_again jsonb;
  v_full jsonb;
  v_full_again jsonb;
  v_partial_receiver jsonb;
  v_partial_depositor jsonb;
  v_full_receiver jsonb;
  v_full_depositor jsonb;
  v_partial_id uuid;
  v_full_id uuid;
  v_groups jsonb;
  v_partial_remaining int;
  v_full_remaining int;
  v_partial_app_mirror boolean:=false;
  v_full_app_mirror boolean:=false;
  v_ready_after int;
  v_despatch_after int;
  v_ledger_after int;
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

  select worker_id into v_line
  from public.rr_worker_directory_compat_v264
  where lower(trim(worker_name))='ali'
    and lower(trim(coalesce(department_code,'')))='fabrication'
    and regexp_replace(lower(trim(coalesce(role_code,''))),'[^a-z]','','g') in ('lineman','linemanager')
    and coalesce(is_active,true)
  order by lower(worker_name),worker_id limit 1;
  if v_line is null then raise exception 'Ali test Line Man mapping unavailable'; end if;

  select b.box_id,b.qty into v_partial_box
  from public.rr_fg_ready_box_v787 b
  where b.data_mode='TEST' and b.lot_no='E2E-FRESH-03'
  order by b.box_code limit 1;
  select count(*) into v_partial_before from public.rr_fg_ready_box_v787
  where data_mode='TEST' and lot_no='E2E-FRESH-03';
  select count(*) into v_full_before from public.rr_fg_ready_box_v787
  where data_mode='TEST' and lot_no='E2E9036-D2-V10';
  if v_partial_box.box_id is null or v_partial_before<2 or v_full_before<1 then
    raise exception 'Reversible Checkpoint 7 ready-box fixtures unavailable';
  end if;
  select count(*) into v_ready_before from public.rr_fg_ready_box_v787
  where data_mode='TEST' and lot_no in ('E2E-FRESH-03','E2E9036-D2-V10');
  select count(*) into v_despatch_before from public.rr_fg_despatch_v787
  where data_mode='TEST';
  select count(*) into v_ledger_before from public.rr_fg_stock_ledger_v787
  where data_mode='TEST';

  begin
    v_partial:=public.rr_fg_create_despatch_chat_v335(
      'E2E-FRESH-03',
      jsonb_build_array(jsonb_build_object('box_id',v_partial_box.box_id,'qty',v_partial_box.qty)),
      v_line,'G1','TEST71 CP7 rollback partial',gen_random_uuid(),'TEST'
    );
    v_partial_id:=(v_partial->>'despatch_id')::uuid;
    v_partial_again:=public.rr_fg_create_despatch_chat_v335(
      'E2E-FRESH-03',
      jsonb_build_array(jsonb_build_object('box_id',v_partial_box.box_id,'qty',v_partial_box.qty)),
      v_line,'G1','TEST71 CP7 rollback partial',(select client_action_id from public.rr_fg_despatch_v787 where id=v_partial_id),'TEST'
    );
    select exists(
      select 1 from public.rr_fg_receive_pending_v787 where despatch_id=v_partial_id
    ) into v_partial_app_mirror;
    select jsonb_agg(jsonb_build_object(
      'id',g.id,'received_box_count',g.box_count,'received_qty',g.expected_qty
    ) order by g.box_from) into v_groups
    from public.rr_fg_despatch_receive_groups_v9356 g
    where g.despatch_id=v_partial_id;
    v_partial_receiver:=public.rr_fg_receive_accept_v9361(
      v_partial_id,v_groups,'RECEIVER','TEST71 CP7 rollback partial receive'
    );
    v_partial_depositor:=public.rr_fg_receive_accept_v9361(
      v_partial_id,v_groups,'DEPOSITOR','TEST71 CP7 rollback partial handover'
    );
    select count(*) into v_partial_remaining from public.rr_fg_ready_box_v787
    where data_mode='TEST' and lot_no='E2E-FRESH-03';

    v_full:=public.rr_fg_create_despatch_chat_v335(
      'E2E9036-D2-V10',null,v_line,'G2','TEST71 CP7 rollback full',gen_random_uuid(),'TEST'
    );
    v_full_id:=(v_full->>'despatch_id')::uuid;
    v_full_again:=public.rr_fg_create_despatch_chat_v335(
      'E2E9036-D2-V10',null,v_line,'G2','TEST71 CP7 rollback full',
      (select client_action_id from public.rr_fg_despatch_v787 where id=v_full_id),'TEST'
    );
    select exists(
      select 1 from public.rr_fg_receive_pending_v787 where despatch_id=v_full_id
    ) into v_full_app_mirror;
    select jsonb_agg(jsonb_build_object(
      'id',g.id,'received_box_count',g.box_count,'received_qty',g.expected_qty
    ) order by g.box_from) into v_groups
    from public.rr_fg_despatch_receive_groups_v9356 g
    where g.despatch_id=v_full_id;
    v_full_receiver:=public.rr_fg_receive_accept_v9361(
      v_full_id,v_groups,'RECEIVER','TEST71 CP7 rollback full receive'
    );
    v_full_depositor:=public.rr_fg_receive_accept_v9361(
      v_full_id,v_groups,'DEPOSITOR','TEST71 CP7 rollback full handover'
    );
    select count(*) into v_full_remaining from public.rr_fg_ready_box_v787
    where data_mode='TEST' and lot_no='E2E9036-D2-V10';
    raise exception '__TEST71_CP7_ROLLBACK__';
  exception when raise_exception then
    if sqlerrm<>'__TEST71_CP7_ROLLBACK__' then raise; end if;
  end;

  select count(*) into v_ready_after from public.rr_fg_ready_box_v787
  where data_mode='TEST' and lot_no in ('E2E-FRESH-03','E2E9036-D2-V10');
  select count(*) into v_despatch_after from public.rr_fg_despatch_v787
  where data_mode='TEST';
  select count(*) into v_ledger_after from public.rr_fg_stock_ledger_v787
  where data_mode='TEST';

  return jsonb_build_object(
    'partial',jsonb_build_object(
      'kind',v_partial->>'kind','boxes',(v_partial->>'total_boxes')::int,
      'duplicate_blocked',(v_partial_again->>'already_locked')::boolean,
      'remaining_ready_during',v_partial_remaining,
      'app_mirror',v_partial_app_mirror,
      'receiver_finalized',(v_partial_receiver->>'finalized')::boolean,
      'depositor_finalized',(v_partial_depositor->>'finalized')::boolean
    ),
    'full',jsonb_build_object(
      'kind',v_full->>'kind','boxes',(v_full->>'total_boxes')::int,
      'expected_boxes',v_full_before,
      'duplicate_blocked',(v_full_again->>'already_locked')::boolean,
      'remaining_ready_during',v_full_remaining,
      'app_mirror',v_full_app_mirror,
      'receiver_finalized',(v_full_receiver->>'finalized')::boolean,
      'depositor_finalized',(v_full_depositor->>'finalized')::boolean
    ),
    'rolled_back',v_ready_after=v_ready_before
      and v_despatch_after=v_despatch_before and v_ledger_after=v_ledger_before,
    'persisted',not(
      v_ready_after=v_ready_before and v_despatch_after=v_despatch_before
      and v_ledger_after=v_ledger_before
    )
  );
end $$;

commit;

