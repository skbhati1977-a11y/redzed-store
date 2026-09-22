-- TEST71 V622: deterministic, isolated browser fixtures for the canonical
-- CB/Product Master/Cutting UI.  Business writers remain canonical.  Fixture
-- retirement preserves purchase, stock-return, Accounts, Art and audit history
-- while removing every active/actionable projection from subsequent runs.
begin;

create or replace function public.rr_test_cb_ui_fixture_v619(
  p_action text,
  p_fixture_key uuid
) returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_action text:=upper(trim(coalesce(p_action,'')));
  v_marker text;
  v_cb_no text;
  v_cb uuid;
  v_parent_operation text;
  v_regular uuid;
  v_regular_entry public.rr_cb_purchase_entries%rowtype;
  v_art uuid;
  v_units uuid[];
  v_assignments uuid[];
  v_payload jsonb;
  v_confirm jsonb;
  v_return jsonb;
  v_profile public.rr_user_profiles%rowtype;
  v_created boolean:=false;
  v_decision_applied boolean:=false;
  v_already_retired boolean:=false;
  v_archived_bridges integer:=0;
  v_archived_events integer:=0;
  v_active_rows integer:=0;
  v_active_units integer:=0;
  v_art_due integer:=0;
  v_actionable_cutting integer:=0;
  v_active_bridges integer:=0;
  v_retained_returns integer:=0;
  u record;
begin
  if p_fixture_key is null then
    raise exception 'Fixture key required.';
  end if;

  -- One exact signed-in TEST71 identity may create or retire these fixtures.
  -- SECURITY DEFINER never replaces this actor/effective-identity check.
  select * into v_profile
  from public.rr_user_profiles
  where auth_user_id=auth.uid()
    and is_active
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE';

  if v_profile.id is null
    or v_profile.full_name<>'TEST71 E2E Super Admin'
    or upper(coalesce(v_profile.role_code,''))<>'SUPER_ADMIN' then
    raise exception 'Dedicated TEST71 E2E Super Admin required.' using errcode='42501';
  end if;

  if coalesce((public.rr_upm_effective_identity_v200()->>'on_behalf')::boolean,false) then
    raise exception 'Return Act As to signed-in TEST71 E2E Super Admin first.' using errcode='42501';
  end if;

  if v_action not in('SETUP','READY','RETIRE','CLEANUP') then
    raise exception 'Use SETUP, READY or RETIRE.';
  end if;

  -- The transaction-scoped key makes SETUP/READY/RETIRE retry-safe without
  -- locking unrelated CBs or creating a lock table.
  perform pg_advisory_xact_lock(
    hashtextextended('RR_TEST_CB_UI_V619:'||p_fixture_key::text,0)
  );

  v_cb_no:='TEST71-UI-'||upper(substr(replace(p_fixture_key::text,'-',''),1,12));
  v_marker:='TEST71 V619 UI FIXTURE:'||p_fixture_key::text;

  select id,operation_status into v_cb,v_parent_operation
  from public.rr_fabric_purchases
  where upper(cb_no)=upper(v_cb_no);

  if v_cb is not null and not exists(
    select 1 from public.rr_fabric_purchases
    where id=v_cb and notes=v_marker
  ) then
    raise exception 'V619 refused: CB identity/marker collision.' using errcode='23505';
  end if;

  if v_action in('RETIRE','CLEANUP') then
    if v_cb is null then
      return jsonb_build_object(
        'ok',true,
        'retired',false,
        'duplicate_blocked',true,
        'active_fixture_rows',0,
        'retained_history_rows',0,
        'cb_no',v_cb_no,
        'fixture_key',p_fixture_key
      );
    end if;

    v_already_retired:=upper(coalesce(v_parent_operation,'ACTIVE'))<>'ACTIVE';

    select array_agg(id order by division_index) into v_units
    from public.rr_cb_units
    where purchase_id=v_cb and coalesce(is_final,true);

    select id into v_art
    from public.rr_art_master
    where is_active
    order by created_at,id
    limit 1;

    if v_art is null then
      raise exception 'V619 requires one active canonical Art.';
    end if;

    -- Finish any pending fixture-only Art work through the canonical Product
    -- Master writer so no retained ART_DUE row pollutes a future browser run.
    for u in
      select x.id
      from public.rr_cb_units x
      left join public.rr_pm_decision_status_v802 d on d.cb_unit_id=x.id
      where x.purchase_id=v_cb
        and coalesce(x.is_final,true)
        and not coalesce(d.all_decisions_complete,false)
      order by x.division_index
    loop
      perform public.rr_pm_save_decision_bundle_v804(
        u.id,v_art,'NA','{}'::uuid[],'NA','{}'::uuid[],'NA','{}'::uuid[],'TEST'
      );
    end loop;

    select p.* into v_regular_entry
    from public.rr_cb_purchase_entries p
    join public.rr_material_categories mc on mc.id=p.material_category_id
    where p.cb_id=v_cb
      and lower(mc.category_code)='regular-cloth'
    order by p.created_at,p.id
    limit 1
    for update of p;

    -- Canonical Purchase Return performs the stock-out and offsetting Accounts
    -- posting once.  Immutable purchase/return/ledger rows are intentionally kept.
    if v_regular_entry.id is not null
      and coalesce(v_regular_entry.available_quantity,0)>0 then
      v_return:=public.rr_cb_purchase_return_v806(
        v_regular_entry.id,
        v_regular_entry.available_quantity,
        'TEST',
        'TEST71 V619 isolated browser fixture retirement',
        null,
        null,
        current_date,
        v_marker
      );
    end if;

    update public.rr_cb_units
    set is_cutting_enabled=false,
        operation_status='TEST_RETIRED',
        status='cancelled',
        updated_at=now()
    where purchase_id=v_cb
      and (
        coalesce(is_cutting_enabled,true)
        or upper(coalesce(operation_status,'ACTIVE'))<>'TEST_RETIRED'
        or status<>'cancelled'
      );

    -- Shared reconciliation owns CB OPEN/WORKING/CLOSE truth while the fixture
    -- is still active; retirement only removes it from active projections.
    perform public.rr_cb_reconcile_department_states_v618();

    update public.rr_fabric_purchases
    set operation_status='TEST_RETIRED'
    where id=v_cb
      and upper(coalesce(operation_status,'ACTIVE'))='ACTIVE';

    select array_agg(id order by id) into v_assignments
    from public.rr_cb_art_assignments
    where cb_id=any(coalesce(v_units,'{}'::uuid[]));

    update public.rr_real_chat_message_bridge_v70 b
    set archived_at=coalesce(b.archived_at,now()),
        archive_reason=coalesce(b.archive_reason,'TEST71 V619 fixture retired')
    where b.archived_at is null
      and b.data_mode='TEST'
      and (
        b.source_record_id=v_cb::text
        or b.source_record_id=any(coalesce(v_units,'{}'::uuid[])::text[])
        or b.source_record_id=any(coalesce(v_assignments,'{}'::uuid[])::text[])
        or b.canonical_event_id in(
          select e.id
          from public.rr_real_chat_canonical_events_v96 e
          where e.parent_id=v_cb::text
            or e.source_record_id=v_cb::text
            or e.source_record_id=any(coalesce(v_units,'{}'::uuid[])::text[])
            or e.source_record_id=any(coalesce(v_assignments,'{}'::uuid[])::text[])
        )
        or b.personal_payload->>'cb_id'=v_cb::text
        or b.group_payload->>'cb_id'=v_cb::text
        or b.personal_payload->>'cb_unit_id'=any(coalesce(v_units,'{}'::uuid[])::text[])
        or b.group_payload->>'cb_unit_id'=any(coalesce(v_units,'{}'::uuid[])::text[])
      );
    get diagnostics v_archived_bridges=row_count;

    update public.rr_real_chat_canonical_events_v96 e
    set archived_at=coalesce(e.archived_at,now()),
        updated_at=now()
    where e.archived_at is null
      and (
        e.parent_id=v_cb::text
        or e.source_record_id=v_cb::text
        or e.source_record_id=any(coalesce(v_units,'{}'::uuid[])::text[])
        or e.source_record_id=any(coalesce(v_assignments,'{}'::uuid[])::text[])
      );
    get diagnostics v_archived_events=row_count;

    select count(*)::integer into v_active_rows
    from public.rr_fabric_purchases
    where id=v_cb and upper(coalesce(operation_status,'ACTIVE'))='ACTIVE';

    select count(*)::integer into v_active_units
    from public.rr_cb_units
    where purchase_id=v_cb and coalesce(is_cutting_enabled,true);

    select count(*)::integer into v_art_due
    from public.rr_pm_decision_status_v802 d
    where d.cb_unit_id=any(coalesce(v_units,'{}'::uuid[]))
      and d.art_status='ART_DUE';

    select count(*)::integer into v_actionable_cutting
    from unnest(coalesce(v_units,'{}'::uuid[])) x(id)
    where public.rr_cutting_child_lifecycle_v615(x.id)->>'state'
      in('ART_DUE','CUTTING_HOLD','READY_FOR_CUTTING');

    select count(*)::integer into v_active_bridges
    from public.rr_real_chat_message_bridge_v70 b
    where b.archived_at is null
      and b.data_mode='TEST'
      and (
        b.source_record_id=v_cb::text
        or b.source_record_id=any(coalesce(v_units,'{}'::uuid[])::text[])
        or b.source_record_id=any(coalesce(v_assignments,'{}'::uuid[])::text[])
        or b.canonical_event_id in(
          select e.id
          from public.rr_real_chat_canonical_events_v96 e
          where e.parent_id=v_cb::text
            or e.source_record_id=v_cb::text
            or e.source_record_id=any(coalesce(v_units,'{}'::uuid[])::text[])
            or e.source_record_id=any(coalesce(v_assignments,'{}'::uuid[])::text[])
        )
        or b.personal_payload->>'cb_id'=v_cb::text
        or b.group_payload->>'cb_id'=v_cb::text
        or b.personal_payload->>'cb_unit_id'=any(coalesce(v_units,'{}'::uuid[])::text[])
        or b.group_payload->>'cb_unit_id'=any(coalesce(v_units,'{}'::uuid[])::text[])
      );

    select count(*)::integer into v_retained_returns
    from public.rr_purchase_returns_v806 r
    where r.source_module='REGULAR_CLOTH'
      and r.source_purchase_id=v_regular_entry.id
      and r.data_mode='TEST';

    return jsonb_build_object(
      'ok',v_active_rows=0 and v_active_units=0 and v_art_due=0
        and v_actionable_cutting=0 and v_active_bridges=0,
      'retired',not v_already_retired,
      'duplicate_blocked',v_already_retired,
      'cb_id',v_cb,
      'cb_no',v_cb_no,
      'fixture_key',p_fixture_key,
      'active_fixture_rows',v_active_rows,
      'active_unit_count',v_active_units,
      'art_due_count',v_art_due,
      'actionable_cutting_count',v_actionable_cutting,
      'active_chat_projection_count',v_active_bridges,
      'archived_bridge_count',v_archived_bridges,
      'archived_event_count',v_archived_events,
      'retained_history_rows',1,
      'retained_purchase_return_count',v_retained_returns,
      'purchase_return',v_return
    );
  end if;

  if v_cb is not null and upper(coalesce(v_parent_operation,'ACTIVE'))<>'ACTIVE' then
    raise exception 'V619 fixture is retired; use a new fixture key.' using errcode='55000';
  end if;

  if v_cb is null then
    if v_action='READY' then
      raise exception 'Run SETUP before READY.';
    end if;

    select id into v_regular
    from public.rr_material_categories
    where lower(category_code)='regular-cloth' and is_active
    order by sort_order,created_at,id
    limit 1;

    if v_regular is null then
      raise exception 'V619 requires canonical Regular Cloth.';
    end if;

    v_payload:=jsonb_build_object(
      'cb_no',v_cb_no,
      'division_count',2,
      'colour_count',1,
      'remarks',v_marker,
      'colours',jsonb_build_array(jsonb_build_object(
        'index',1,
        'name','TEST71 UI Colour',
        'image_url',null,
        'confirmed',true
      )),
      'regular',jsonb_build_object(
        'client_key',gen_random_uuid(),
        'category_id',v_regular,
        'vendor','TEST71 Supplier',
        'bill_no',v_cb_no,
        'bill_date',current_date,
        'fabric_name','TEST71 Regular Cloth',
        'qty',120,
        'rate',365,
        'amount',43800,
        'rolls',jsonb_build_array(jsonb_build_object(
          'colour_index',1,'roll_no',1,'qty',120
        ))
      ),
      'materials','[]'::jsonb
    );

    v_confirm:=public.rr_cb_department_save_v600(
      null,p_fixture_key,true,v_payload
    );
    v_cb:=(v_confirm->>'cb_id')::uuid;
    v_created:=true;
  end if;

  select array_agg(id order by division_index) into v_units
  from public.rr_cb_units
  where purchase_id=v_cb and coalesce(is_final,true);

  if coalesce(array_length(v_units,1),0)<>2 then
    raise exception 'V619 expected two canonical CB children.';
  end if;

  if v_action='READY' then
    select id into v_art
    from public.rr_art_master
    where is_active
    order by created_at,id
    limit 1;

    if v_art is null then
      raise exception 'V619 requires one active canonical Art.';
    end if;

    if not coalesce((
      select d.all_decisions_complete
      from public.rr_pm_decision_status_v802 d
      where d.cb_unit_id=v_units[2]
    ),false) then
      perform public.rr_pm_save_decision_bundle_v804(
        v_units[2],v_art,'NA','{}'::uuid[],'NA','{}'::uuid[],'NA','{}'::uuid[],'TEST'
      );
      v_decision_applied:=true;
    end if;
  end if;

  return jsonb_build_object(
    'ok',true,
    'cb_id',v_cb,
    'cb_no',v_cb_no,
    'fixture_key',p_fixture_key,
    'setup_applied',v_created,
    'setup_duplicate_blocked',not v_created,
    'ready_decision_applied',v_decision_applied,
    'ready_duplicate_blocked',v_action='READY' and not v_decision_applied,
    'art_due_unit_id',v_units[1],
    'ready_unit_id',v_units[2],
    'art_due_lifecycle',public.rr_cutting_child_lifecycle_v615(v_units[1]),
    'ready_lifecycle',public.rr_cutting_child_lifecycle_v615(v_units[2]),
    'fixture_rows',(
      select count(*) from public.rr_fabric_purchases where id=v_cb
    )
  );
end
$function$;

alter function public.rr_test_cb_ui_fixture_v619(text,uuid)
  set statement_timeout='30s';

revoke all on function public.rr_test_cb_ui_fixture_v619(text,uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.rr_test_cb_ui_fixture_v619(text,uuid)
  to authenticated;

comment on function public.rr_test_cb_ui_fixture_v619(text,uuid) is
  'TEST71 V622 authenticated browser fixture. SETUP/READY use canonical CB and Product Master writers; RETIRE uses canonical Purchase Return, preserves immutable TEST history, and removes active App/Real Chat/Cutting projections.';

notify pgrst,'reload schema';
commit;
