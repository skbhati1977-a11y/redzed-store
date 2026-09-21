-- TEST71 V502: a released Cutting D-card is history, never actionable work.
-- Keeps the canonical release engines and UPM assignment queue unchanged.

begin;

-- The old production gallery projected rr_cb_units.status only.  That status is
-- intentionally reused by downstream Cutting, so permanent Lot truth must win.
create or replace view public.rr_product_gallery_production_v719 as
with lot_rows as (
  select l.cb_unit_id,l.lot_no,lower(coalesce(l.status,'')) as status
  from public.rr_cutting_lots_v3 l
  where upper(coalesce(l.status,'')) not in ('CANCELLED','CANCELED')
  union all
  select l.cb_unit_id,l.lot_no,lower(coalesce(l.status,'')) as status
  from public.rr_production_lots l
  where upper(coalesce(l.status,'')) not in ('CANCELLED','CANCELED')
), lot_truth as (
  select
    l.cb_unit_id,
    string_agg(distinct nullif(btrim(l.lot_no),''),', ' order by nullif(btrim(l.lot_no),'')) as lot_no,
    bool_or(l.status='completed') as has_completed,
    count(*)>0 as has_lot
  from lot_rows l
  group by l.cb_unit_id
)
select
  g.cb_id,
  g.cb_no,
  g.division_id,
  g.division_code,
  case
    when coalesce(t.has_completed,false) then 'completed'
    when coalesce(t.has_lot,false) then 'released'
    else g.division_status
  end as division_status,
  g.allocated_qty,
  g.allocated_amount,
  coalesce(t.lot_no,g.lot_no) as lot_no,
  g.created_at,
  g.division_index,
  g.base_qty,
  g.base_amount
from public.rr_product_gallery_view g
join public.rr_fabric_purchases fp on fp.id::text=g.cb_id::text
left join lot_truth t on t.cb_unit_id=g.division_id
where coalesce(fp.card_type,'production_cb')='production_cb'
  and coalesce(fp.is_cutting_enabled,true)=true;

-- Serialize both physical release modes on the canonical CB child and reject a
-- cross-mode retry before either table can create a second release identity.
create or replace function public.rr_guard_cutting_release_mode_v502()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
begin
  if new.cb_unit_id is null then return new; end if;

  perform 1 from public.rr_cb_units u where u.id=new.cb_unit_id for update;
  if not found then raise exception 'CB Child not found'; end if;

  if tg_table_name='rr_cutting_lots_v3' then
    if exists(
      select 1 from public.rr_production_lots p
      where p.cb_unit_id=new.cb_unit_id
        and lower(coalesce(p.lot_mode,'multi'))='multi'
        and upper(coalesce(p.status,'')) not in ('CANCELLED','CANCELED')
    ) then
      raise exception 'This CB Child is already released across MULTI LOT mode'
        using errcode='23505';
    end if;
  elsif tg_table_name='rr_production_lots'
        and lower(coalesce(new.lot_mode,''))='multi' then
    if exists(
      select 1 from public.rr_cutting_lots_v3 s
      where s.cb_unit_id=new.cb_unit_id
        and upper(coalesce(s.status,'')) not in ('CANCELLED','CANCELED')
    ) then
      raise exception 'This CB Child is already released across SINGLE LOT mode'
        using errcode='23505';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists rr_000_cutting_release_cross_mode_v502 on public.rr_cutting_lots_v3;
create trigger rr_000_cutting_release_cross_mode_v502
before insert on public.rr_cutting_lots_v3
for each row execute function public.rr_guard_cutting_release_mode_v502();

drop trigger if exists rr_000_cutting_release_cross_mode_v502 on public.rr_production_lots;
create trigger rr_000_cutting_release_cross_mode_v502
before insert on public.rr_production_lots
for each row execute function public.rr_guard_cutting_release_mode_v502();

revoke all on function public.rr_guard_cutting_release_mode_v502() from public,anon,authenticated;
grant execute on function public.rr_guard_cutting_release_mode_v502() to service_role;

update public.rr_real_chat_action_registry_v70
set success_state='CLOSE',next_action_code=null,updated_at=now(),
    notes='Cutting release closes the D-card. Downstream assignment remains in the canonical UPM queue.'
where action_code in ('CUTTING_SINGLE_LOT','CUTTING_MULTI_LOT');

create or replace function public.rr_real_chat_reconcile_cutting_v113()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_open integer:=0;
  v_stale integer:=0;
  v_released integer:=0;
begin
  -- Defensive cleanup: even if an older trigger left READY active, Lot truth
  -- makes that action terminal and preserves it only as archived history.
  update public.rr_real_chat_message_bridge_v70 b
  set archived_at=coalesce(b.archived_at,now()),
      archive_reason='LOT_RELEASED_CANONICAL_CLOSE',
      action_code=null,
      action_label=null
  where b.archived_at is null
    and b.source_module='CUTTING'
    and b.source_event_type='READY_FOR_CUTTING'
    and (
      exists(select 1 from public.rr_cutting_lots_v3 l where l.cb_unit_id::text=b.source_record_id and upper(coalesce(l.status,'')) not in ('CANCELLED','CANCELED'))
      or exists(select 1 from public.rr_production_lots l where l.cb_unit_id::text=b.source_record_id and upper(coalesce(l.status,'')) not in ('CANCELLED','CANCELED'))
    );
  get diagnostics v_stale=row_count;

  update public.rr_real_chat_message_bridge_v70 b
  set action_code='CUTTING_SINGLE_LOT',action_label='SINGLE LOT',
      personal_payload=(coalesce(b.personal_payload,'{}'::jsonb)-'next_actions')||jsonb_build_object(
        'canonical_state','OPEN','status','OPEN','message','Art / Print decision complete — Cutting Lot बनाना बाकी है',
        'next_actions',jsonb_build_array(
          jsonb_build_object('code','CUTTING_SINGLE_LOT','label','SINGLE LOT','href','real-cutting-master.html?cb_unit_id='||b.source_record_id||'&lot_mode=single','engine','EXISTING_CUTTING_RELEASE_CHAIN','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER')),
          jsonb_build_object('code','CUTTING_MULTI_LOT','label','MULTI LOT','href','real-cutting-master.html?cb_unit_id='||b.source_record_id||'&lot_mode=multi','engine','EXISTING_CUTTING_RELEASE_CHAIN','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER')))),
      group_payload=(coalesce(b.group_payload,'{}'::jsonb)-'next_actions')||jsonb_build_object(
        'canonical_state','OPEN','status','OPEN','message','Art / Print decision complete — Cutting Lot बनाना बाकी है',
        'next_actions',jsonb_build_array(
          jsonb_build_object('code','CUTTING_SINGLE_LOT','label','SINGLE LOT','href','real-cutting-master.html?cb_unit_id='||b.source_record_id||'&lot_mode=single','engine','EXISTING_CUTTING_RELEASE_CHAIN','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER')),
          jsonb_build_object('code','CUTTING_MULTI_LOT','label','MULTI LOT','href','real-cutting-master.html?cb_unit_id='||b.source_record_id||'&lot_mode=multi','engine','EXISTING_CUTTING_RELEASE_CHAIN','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER')))),
      deep_link='real-cutting-master.html?cb_unit_id='||b.source_record_id||'&lot_mode=single'
  where b.archived_at is null
    and b.source_module='CUTTING'
    and b.source_event_type='READY_FOR_CUTTING'
    and not exists(select 1 from public.rr_cutting_lots_v3 l where l.cb_unit_id::text=b.source_record_id and upper(coalesce(l.status,'')) not in ('CANCELLED','CANCELED'))
    and not exists(select 1 from public.rr_production_lots l where l.cb_unit_id::text=b.source_record_id and upper(coalesce(l.status,'')) not in ('CANCELLED','CANCELED'));
  get diagnostics v_open=row_count;

  with released as (
    select b0.id as bridge_id,l.lot_no
    from public.rr_real_chat_message_bridge_v70 b0
    join public.rr_upm_lot_registry l on l.id::text=b0.source_record_id
    where b0.archived_at is null
      and b0.source_module='CUTTING'
      and b0.source_event_type='CUTTING_RELEASE_SUCCEEDED'
  )
  update public.rr_real_chat_message_bridge_v70 b
  set personal_payload=(coalesce(b.personal_payload,'{}'::jsonb)-'next_actions'-'action_href')||jsonb_build_object(
        'canonical_state','CLOSE','status','CLOSE',
        'message','Cutting release complete — D-card history closed; downstream assignment canonical UPM queue में है',
        'next_actions','[]'::jsonb,'allowed_roles','[]'::jsonb),
      group_payload=(coalesce(b.group_payload,'{}'::jsonb)-'next_actions'-'action_href')||jsonb_build_object(
        'canonical_state','CLOSE','status','CLOSE',
        'message','Cutting release complete — D-card history closed; downstream assignment canonical UPM queue में है',
        'next_actions','[]'::jsonb,'allowed_roles','[]'::jsonb),
      action_code=null,
      action_label=null
  from released r
  where b.id=r.bridge_id;
  get diagnostics v_released=row_count;

  return jsonb_build_object(
    'cutting_open',v_open,
    'stale_ready_archived',v_stale,
    'cutting_released',v_released,
    'working_unassigned',(select count(*) from public.rr_real_chat_message_bridge_v70 where archived_at is null and source_module='CUTTING' and source_event_type='CUTTING_RELEASE_SUCCEEDED' and personal_payload->>'canonical_state'='WORKING'),
    'closed_assigned',(select count(*) from public.rr_real_chat_message_bridge_v70 where archived_at is null and source_module='CUTTING' and source_event_type='CUTTING_RELEASE_SUCCEEDED' and personal_payload->>'canonical_state'='CLOSE'),
    'closed_released',(select count(*) from public.rr_real_chat_message_bridge_v70 where archived_at is null and source_module='CUTTING' and source_event_type='CUTTING_RELEASE_SUCCEEDED' and personal_payload->>'canonical_state'='CLOSE')
  );
end $$;

revoke all on function public.rr_real_chat_reconcile_cutting_v113() from public,anon,authenticated;
grant execute on function public.rr_real_chat_reconcile_cutting_v113() to service_role;

-- Authenticated TEST E2E Super Admin only.  Every fixture and triggered side
-- effect lives inside an exception subtransaction and is verified as absent.
create or replace function public.rr_test_released_dcard_regression_v502()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_profile record;
  v_purchase uuid;
  v_colour uuid;
  v_art uuid;
  v_art_no text;
  v_unit uuid:=gen_random_uuid();
  v_code text;
  v_lot text;
  v_first uuid;
  v_second_blocked boolean:=false;
  v_cross_mode_blocked boolean:=false;
  v_retry_error text;
  v_cross_error text;
  v_single_count int:=0;
  v_gallery_state text;
  v_gallery_lot text;
  v_open_count int:=0;
  v_history_count int:=0;
  v_chat_state text;
  v_chat_action text;
  v_chat_next jsonb;
  v_residue int:=0;
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

  select p.id,c.id into v_purchase,v_colour
  from public.rr_fabric_purchases p
  join public.rr_cb_colours c on c.cb_id=p.id
  where upper(coalesce(p.cb_no,'')) like 'E2E%'
     or upper(coalesce(p.cb_no,'')) like '%TEST%'
     or upper(coalesce(p.notes,'')) like '%TEST%'
  order by p.created_at,c.col_no
  limit 1;
  select a.id,a.art_no into v_art,v_art_no
  from public.rr_art_master_core_v402 a
  where coalesce(a.is_active,true)
  order by (lower(a.art_no) like 'test%') desc,a.created_at
  limit 1;
  if v_purchase is null or v_colour is null or v_art is null then
    raise exception 'Reversible Cutting TEST source unavailable';
  end if;

  v_code:='TEST71-DCARD-'||upper(substr(replace(v_unit::text,'-',''),1,8));
  v_lot:='T71D'||upper(substr(replace(v_unit::text,'-',''),1,10));

  begin
    insert into public.rr_cb_units(
      id,purchase_id,cb_base_no,division_count,division_index,cb_code,
      divided_rolls,divided_weight,divided_amount,status,is_final,notes
    ) values(
      v_unit,v_purchase,v_code,1,1,v_code||'-D1',1,1,0,'art_assigned',true,
      'TEST71 V502 rollback-only released D-card regression'
    );

    insert into public.rr_cb_art_assignments(
      cb_id,art_id,status,print_not_applicable,sticker_not_applicable,metal_id_not_applicable,
      print_due,sticker_due,metal_id_due
    ) values(
      v_unit,v_art,'ready_for_cutting',true,true,true,false,false,false
    );

    perform public.rr_save_cutting_lot_draft_v1(
      v_purchase,v_unit,'single',v_lot,
      jsonb_build_object('source','TEST71_V502_ROLLBACK','lot_no',v_lot),
      'OPEN',null,null
    );

    v_first:=public.rr_release_single_lot_v3(
      v_lot,v_unit,current_date,'TEST71 D-card regression',v_art_no,'N/A','TEST E2E',
      array['L']::text[],1,1,0,0,0,'small','half','without',0,
      'TEST71 V502 rollback-only first release',
      jsonb_build_array(jsonb_build_object(
        'cb_colour_id',v_colour::text,'colour_name','TEST COLOUR','size_code','L','qty',1
      ))
    );

    perform public.rr_real_chat_reconcile_cutting_v113();

    select count(*) into v_single_count
    from public.rr_cutting_lots_v3 where cb_unit_id=v_unit;
    select division_status,lot_no into v_gallery_state,v_gallery_lot
    from public.rr_product_gallery_production_v719 where division_id=v_unit;
    select count(*) into v_open_count
    from public.rr_real_chat_message_bridge_v70
    where archived_at is null and source_module='CUTTING'
      and source_event_type='READY_FOR_CUTTING' and source_record_id=v_unit::text;
    select count(*),max(b.personal_payload->>'canonical_state'),max(b.action_code),
           max((b.personal_payload->'next_actions')::text)::jsonb
      into v_history_count,v_chat_state,v_chat_action,v_chat_next
    from public.rr_real_chat_message_bridge_v70 b
    join public.rr_upm_lot_registry l on l.id::text=b.source_record_id
    where b.archived_at is null and b.source_module='CUTTING'
      and b.source_event_type='CUTTING_RELEASE_SUCCEEDED' and upper(l.lot_no)=upper(v_lot);

    begin
      perform public.rr_release_single_lot_v3(
        v_lot,v_unit,current_date,'TEST71 D-card regression',v_art_no,'N/A','TEST E2E',
        array['L']::text[],1,1,0,0,0,'small','half','without',0,
        'TEST71 V502 rollback-only retry',
        jsonb_build_array(jsonb_build_object(
          'cb_colour_id',v_colour::text,'colour_name','TEST COLOUR','size_code','L','qty',1
        ))
      );
    exception when others then
      v_retry_error:=sqlerrm;
      v_second_blocked:=sqlerrm ilike '%already%';
    end;

    begin
      insert into public.rr_production_lots(lot_no,cb_unit_id,lot_mode,status)
      values(v_lot||'M',v_unit,'multi','released');
    exception when others then
      v_cross_error:=sqlerrm;
      v_cross_mode_blocked:=sqlerrm ilike '%already released across SINGLE LOT mode%';
    end;

    if v_first is null or v_single_count<>1 or not v_second_blocked or not v_cross_mode_blocked
       or v_gallery_state<>'released' or position(v_lot in coalesce(v_gallery_lot,''))=0
       or v_open_count<>0 or v_history_count<>1 or v_chat_state<>'CLOSE'
       or v_chat_action is not null or coalesce(jsonb_array_length(v_chat_next),0)<>0 then
      raise exception 'Released D-card invariant failed';
    end if;

    raise exception '__TEST71_V502_ROLLBACK__';
  exception when raise_exception then
    if sqlerrm<>'__TEST71_V502_ROLLBACK__' then raise; end if;
  end;

  select
    (select count(*) from public.rr_cb_units where id=v_unit)
    +(select count(*) from public.rr_cutting_lots_v3 where cb_unit_id=v_unit)
    +(select count(*) from public.rr_production_lots where cb_unit_id=v_unit)
    +(select count(*) from public.rr_cutting_lot_drafts_v1 where division_id=v_unit)
    +(select count(*) from public.rr_cb_art_assignments where cb_id=v_unit)
    +(select count(*) from public.rr_upm_lot_registry where upper(lot_no)=upper(v_lot))
    +(select count(*) from public.rr_real_chat_message_bridge_v70 where personal_payload->>'lot_no'=v_lot or group_payload->>'lot_no'=v_lot)
  into v_residue;

  return jsonb_build_object(
    'first_release_count',v_single_count,
    'first_release_id',v_first,
    'retry_blocked',v_second_blocked,
    'retry_error',v_retry_error,
    'cross_mode_retry_blocked',v_cross_mode_blocked,
    'cross_mode_error',v_cross_error,
    'gallery_state',v_gallery_state,
    'gallery_lot',v_gallery_lot,
    'actionable_ready_count',v_open_count,
    'history_count',v_history_count,
    'real_chat_state',v_chat_state,
    'real_chat_action',v_chat_action,
    'real_chat_next_actions',coalesce(v_chat_next,'[]'::jsonb),
    'rolled_back',v_residue=0,
    'fixture_residue',v_residue
  );
end $$;

revoke all on function public.rr_test_released_dcard_regression_v502() from public,anon;
grant execute on function public.rr_test_released_dcard_regression_v502() to authenticated,service_role;

select public.rr_real_chat_reconcile_cutting_v113();

commit;
