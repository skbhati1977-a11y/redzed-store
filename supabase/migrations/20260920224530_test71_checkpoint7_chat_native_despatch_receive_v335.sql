-- TEST71 Checkpoint 7 · chat-native Despatch and Store Receive.
-- The existing Finished Goods tables and V787/V7981/V9356 engines remain the
-- only workflow state.  V335 adds an atomic chat adapter, effective Act As
-- authorization, retry identity, and repairs the canonical receive writer.

begin;

alter table public.rr_fg_despatch_v787
  add column if not exists client_action_id uuid,
  add column if not exists client_action_kind text;

create unique index if not exists rr_fg_despatch_v787_client_action_uidx
  on public.rr_fg_despatch_v787(data_mode,client_action_id)
  where client_action_id is not null;

create or replace function public.rr_fg_effective_despatch_access_v335(
  p_despatch_id uuid default null
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_identity jsonb;
  v_role text;
  v_worker_id uuid;
  v_effective_auth_id uuid;
  v_line_worker_id uuid;
  v_line_auth_id uuid;
  v_is_line_man boolean:=false;
begin
  perform public.rr_fg_assert_user_v787();
  v_identity:=public.rr_upm_effective_identity_v200();
  v_role:=regexp_replace(
    upper(coalesce(v_identity->>'role_code',v_identity->>'resolved_role','')),
    '[^A-Z0-9]+','_','g'
  );
  v_role:=trim(both '_' from v_role);
  v_worker_id:=nullif(v_identity->>'worker_id','')::uuid;
  v_effective_auth_id:=nullif(v_identity->>'effective_auth_user_id','')::uuid;

  if p_despatch_id is not null then
    select c.line_man_worker_id,w.linked_auth_user_id
      into v_line_worker_id,v_line_auth_id
    from public.rr_fg_despatch_custody_v9361 c
    left join public.rr_worker_directory_compat_v264 w
      on w.worker_id=c.line_man_worker_id
    where c.despatch_id=p_despatch_id;
    v_is_line_man:=
      coalesce(v_worker_id=v_line_worker_id,false)
      or coalesce(v_effective_auth_id=v_line_auth_id,false);
  end if;

  return jsonb_build_object(
    'role_code',v_role,
    'worker_id',v_worker_id,
    'effective_auth_user_id',v_effective_auth_id,
    'operator_user_id',auth.uid(),
    'on_behalf',coalesce((v_identity->>'on_behalf')::boolean,false),
    'is_delivery_line_man',v_is_line_man,
    'can_create',v_role in (
      'OWNER','SUPER_ADMIN','ADMIN','MANAGER','PACKER','PACKING','PACKING_OPERATOR'
    ),
    'can_receive',v_role in (
      'OWNER','SUPER_ADMIN','ADMIN','MANAGER','STORE','STORE_OPERATOR',
      'SALES','SALESMAN','ACCOUNTS','ACCOUNT'
    ),
    'can_deposit',v_role in ('OWNER','SUPER_ADMIN','ADMIN') or v_is_line_man
  );
end $$;

revoke all on function public.rr_fg_effective_despatch_access_v335(uuid)
  from public,anon,authenticated;

create or replace function public.rr_fg_despatch_action_context_v335(
  p_despatch_id uuid default null
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_access jsonb;
  v_row record;
begin
  v_access:=public.rr_fg_effective_despatch_access_v335(p_despatch_id);
  if p_despatch_id is null then
    return v_access||jsonb_build_object('phase','CREATE');
  end if;
  select d.challan_no,d.status,d.destination,c.line_man_worker_id,c.line_man_name,
         coalesce(a.receiver_accepted,false) receiver_accepted,
         coalesce(a.depositor_accepted,false) depositor_accepted,
         coalesce(a.finalized,false) finalized
    into v_row
  from public.rr_fg_despatch_v787 d
  left join public.rr_fg_despatch_custody_v9361 c on c.despatch_id=d.id
  left join public.rr_fg_despatch_acceptance_v9356 a on a.despatch_id=d.id
  where d.id=p_despatch_id;
  if not found then raise exception 'Challan not found'; end if;
  return v_access||jsonb_build_object(
    'despatch_id',p_despatch_id,'challan_no',v_row.challan_no,
    'status',v_row.status,'destination',v_row.destination,
    'line_man_worker_id',v_row.line_man_worker_id,'line_man_name',v_row.line_man_name,
    'receiver_accepted',v_row.receiver_accepted,
    'depositor_accepted',v_row.depositor_accepted,'finalized',v_row.finalized,
    'phase',case
      when v_row.finalized then 'CLOSE'
      when not v_row.receiver_accepted then 'RECEIVER_VERIFY'
      when not v_row.depositor_accepted then 'DELIVERY_CONFIRM'
      else 'FINALIZING'
    end
  );
end $$;

create or replace function public.rr_fg_despatch_ready_boxes_v335(
  p_lot_no text,
  p_data_mode text default 'TEST'
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_access jsonb;
  v_out jsonb;
begin
  v_access:=public.rr_fg_effective_despatch_access_v335(null);
  if not coalesce((v_access->>'can_create')::boolean,false) then
    raise exception 'Effective Packing/Manager authorization required';
  end if;
  if upper(coalesce(p_data_mode,'')) not in ('TEST','REAL') then
    raise exception 'Invalid data mode';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'box_id',b.box_id,'box_code',b.box_code,'lot_no',b.lot_no,
    'box_type',case when upper(coalesce(b.box_type,''))='REGULAR' then 'FRESH' else upper(b.box_type) end,
    'qty',b.qty
  ) order by b.box_code),'[]'::jsonb)
  into v_out
  from public.rr_fg_ready_box_v787 b
  where b.data_mode=upper(p_data_mode) and b.lot_no=trim(p_lot_no);
  return v_out;
end $$;

create or replace function public.rr_fg_ensure_despatch_groups_v335(
  p_despatch_id uuid
) returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_count integer:=0;
begin
  if exists(
    select 1 from public.rr_fg_despatch_receive_groups_v9356
    where despatch_id=p_despatch_id
  ) then return 0; end if;

  with b0 as (
    select b.*,
      coalesce(
        (regexp_match(b.box_code,'-BOX-([0-9]+)$'))[1]::int,
        row_number() over(order by b.box_code)::int
      ) box_no,
      case
        when exists(select 1 from jsonb_array_elements(coalesce(b.composition,'[]'::jsonb)) e where upper(coalesce(e->>'pack_mark',''))='MIX') then 'MIX'
        when exists(select 1 from jsonb_array_elements(coalesce(b.composition,'[]'::jsonb)) e where upper(coalesce(e->>'pack_mark',''))='ASST') then 'ASST'
        when exists(select 1 from jsonb_array_elements(coalesce(b.composition,'[]'::jsonb)) e where upper(coalesce(e->>'pack_mark',''))='FRESH') then 'REGULAR'
        else case when upper(coalesce(b.box_type,'')) in ('FRESH','REGULAR') then 'REGULAR' else upper(coalesce(b.box_type,'')) end
      end effective_type,
      md5(
        (case
          when exists(select 1 from jsonb_array_elements(coalesce(b.composition,'[]'::jsonb)) e where upper(coalesce(e->>'pack_mark',''))='MIX') then 'MIX'
          when exists(select 1 from jsonb_array_elements(coalesce(b.composition,'[]'::jsonb)) e where upper(coalesce(e->>'pack_mark',''))='ASST') then 'ASST'
          when exists(select 1 from jsonb_array_elements(coalesce(b.composition,'[]'::jsonb)) e where upper(coalesce(e->>'pack_mark',''))='FRESH') then 'REGULAR'
          else case when upper(coalesce(b.box_type,'')) in ('FRESH','REGULAR') then 'REGULAR' else upper(coalesce(b.box_type,'')) end
        end)||'|'||b.qty||'|'||coalesce((
          select jsonb_agg(e-'box_no' order by e->>'colour_code',e->>'size_code',e->>'qty',e->>'pack_mark')::text
          from jsonb_array_elements(coalesce(b.composition,'[]'::jsonb)) e
        ),'')
      ) comp_key
    from public.rr_fg_despatch_boxes_v787 db
    join public.rr_fg_boxes_v787 b on b.id=db.box_id
    where db.despatch_id=p_despatch_id
  ), b1 as (
    select b0.*,box_no-row_number() over(partition by comp_key order by box_no) grp_seq
    from b0
  ), g as (
    select comp_key,grp_seq,max(lot_no) lot_no,
      case when upper(max(effective_type))='REGULAR' then 'REGULAR' else upper(max(effective_type)) end stock_type,
      case when upper(max(effective_type))='REGULAR' then 'FRESH' else upper(max(effective_type)) end display_type,
      min(box_no) box_from,max(box_no) box_to,count(*)::int box_count,
      sum(qty)::int expected_qty,array_agg(id order by box_no) box_ids
    from b1 group by comp_key,grp_seq
  ), ins as (
    insert into public.rr_fg_despatch_receive_groups_v9356(
      despatch_id,group_key,lot_no,stock_type,display_type,box_ids,
      box_from,box_to,box_count,expected_qty
    )
    select p_despatch_id,comp_key||':'||grp_seq,lot_no,stock_type,display_type,
           box_ids,box_from,box_to,box_count,expected_qty
    from g
    returning 1
  ) select count(*) into v_count from ins;

  insert into public.rr_fg_despatch_acceptance_v9356(despatch_id)
  values(p_despatch_id) on conflict do nothing;
  return v_count;
end $$;

revoke all on function public.rr_fg_ensure_despatch_groups_v335(uuid)
  from public,anon,authenticated;

create or replace function public.rr_fg_create_despatch_chat_v335(
  p_lot_no text,
  p_boxes jsonb,
  p_line_man_worker_id uuid,
  p_destination text,
  p_remarks text,
  p_action_id uuid,
  p_data_mode text default 'TEST'
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_mode text:=upper(coalesce(p_data_mode,'TEST'));
  v_lot text:=trim(coalesce(p_lot_no,''));
  v_access jsonb;
  v_existing public.rr_fg_despatch_v787%rowtype;
  v_line record;
  v_packer_worker_id uuid;
  v_packer_name text;
  v_packer_code text;
  v_box jsonb;
  v_box_lot text;
  v_result jsonb;
  v_despatch_id uuid;
  v_full boolean:=p_boxes is null;
  v_total_boxes integer;
  v_total_qty integer;
begin
  v_access:=public.rr_fg_effective_despatch_access_v335(null);
  if not coalesce((v_access->>'can_create')::boolean,false) then
    raise exception 'Effective Packing/Manager authorization required';
  end if;
  if v_mode not in ('TEST','REAL') then raise exception 'Invalid data mode'; end if;
  if v_lot='' then raise exception 'Lot required'; end if;
  if p_action_id is null then raise exception 'Action identity required'; end if;
  if p_destination not in ('G1','G2','G3','G4') then raise exception 'Destination required'; end if;
  if nullif(trim(coalesce(p_remarks,'')),'') is null then raise exception 'Remarks required'; end if;
  if p_line_man_worker_id is null then raise exception 'Delivery Line Man required'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_action_id::text,335));
  select * into v_existing
  from public.rr_fg_despatch_v787
  where data_mode=v_mode and client_action_id=p_action_id;
  if found then
    select count(*),coalesce(sum(b.qty),0)
      into v_total_boxes,v_total_qty
    from public.rr_fg_despatch_boxes_v787 db
    join public.rr_fg_boxes_v787 b on b.id=db.box_id
    where db.despatch_id=v_existing.id;
    return jsonb_build_object(
      'despatch_id',v_existing.id,'challan_no',v_existing.challan_no,
      'total_boxes',v_total_boxes,'total_qty',v_total_qty,
      'kind',v_existing.client_action_kind,'already_locked',true
    );
  end if;

  select w.worker_id,w.worker_code,w.worker_name,w.linked_auth_user_id
    into v_line
  from public.rr_worker_directory_compat_v264 w
  where w.worker_id=p_line_man_worker_id
    and coalesce(w.is_active,true)
    and coalesce(lower(w.access_status),'active') not in ('blocked','inactive')
    and lower(trim(coalesce(w.department_code,'')))='fabrication'
    and regexp_replace(lower(trim(coalesce(w.role_code,''))),'[^a-z]','','g') in ('lineman','linemanager')
  limit 1;
  if not found then raise exception 'Only active Fabrication Line Man allowed'; end if;

  if not v_full then
    if jsonb_typeof(p_boxes)<>'array' or jsonb_array_length(p_boxes)=0 then
      raise exception 'Partial box selection required';
    end if;
    for v_box in select * from jsonb_array_elements(p_boxes) loop
      select b.lot_no into v_box_lot
      from public.rr_fg_ready_box_v787 b
      where b.box_id=nullif(v_box->>'box_id','')::uuid
        and b.data_mode=v_mode;
      if not found then raise exception 'Selected Box ready list me nahi hai'; end if;
      if trim(v_box_lot)<>v_lot then raise exception 'All selected boxes must belong to Lot %',v_lot; end if;
    end loop;
    v_result:=public.rr_fg_create_despatch_v7981(
      p_boxes,p_destination,p_remarks,v_mode
    );
  else
    v_result:=public.rr_fg_create_despatch_lot_v9356(
      v_lot,p_destination,p_remarks,v_mode
    );
  end if;
  v_despatch_id:=(v_result->>'despatch_id')::uuid;

  select a.worker_user_id,a.worker_name,a.worker_code
    into v_packer_worker_id,v_packer_name,v_packer_code
  from public.rr_fg_packing_assignments_v788 a
  where a.data_mode=v_mode and a.lot_no=v_lot and a.status='SUBMITTED'
  order by a.submitted_at desc nulls last,a.assigned_at desc limit 1;

  insert into public.rr_fg_despatch_custody_v9361(
    despatch_id,lot_no,packer_worker_id,packer_name,packer_code,
    line_man_worker_id,line_man_name,line_man_code,created_by
  ) values(
    v_despatch_id,v_lot,v_packer_worker_id,v_packer_name,v_packer_code,
    v_line.worker_id,v_line.worker_name,v_line.worker_code,auth.uid()
  ) on conflict(despatch_id) do update set
    line_man_worker_id=excluded.line_man_worker_id,
    line_man_name=excluded.line_man_name,
    line_man_code=excluded.line_man_code;

  perform public.rr_fg_ensure_despatch_groups_v335(v_despatch_id);
  update public.rr_fg_despatch_v787
  set client_action_id=p_action_id,
      client_action_kind=case when v_full then 'FULL_LOT' else 'PARTIAL' end
  where id=v_despatch_id;

  return v_result||jsonb_build_object(
    'lot_no',v_lot,'kind',case when v_full then 'FULL_LOT' else 'PARTIAL' end,
    'line_man_worker_id',v_line.worker_id,'line_man_name',v_line.worker_name,
    'already_locked',false,'performed_by',auth.uid(),
    'act_as_worker_id',v_access->>'worker_id'
  );
end $$;

create or replace function public.rr_fg_despatch_line_men_v9361()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare v_out jsonb;
begin
  perform public.rr_fg_assert_user_v787();
  select coalesce(jsonb_agg(jsonb_build_object(
    'worker_id',w.worker_id,'worker_code',w.worker_code,'worker_name',w.worker_name,
    'department_code',w.department_code,'role_code',w.role_code
  ) order by lower(w.worker_name),w.worker_code),'[]'::jsonb)
  into v_out
  from public.rr_worker_directory_compat_v264 w
  where coalesce(w.is_active,true)
    and coalesce(lower(w.access_status),'active') not in('blocked','inactive')
    and lower(trim(coalesce(w.department_code,'')))='fabrication'
    and regexp_replace(lower(trim(coalesce(w.role_code,''))),'[^a-z]','','g') in('lineman','linemanager');
  return v_out;
end $$;

create or replace function public.rr_fg_set_receive_destination_v9397(
  p_despatch_id uuid,
  p_destination text
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_access jsonb;
  v_dest text:=trim(coalesce(p_destination,''));
  v_row public.rr_fg_despatch_v787%rowtype;
begin
  v_access:=public.rr_fg_effective_despatch_access_v335(p_despatch_id);
  if not coalesce((v_access->>'can_receive')::boolean,false) then
    raise exception 'Effective Store/Sales/Admin authorization required';
  end if;
  if v_dest not in ('G1','G2','G3','G4') then raise exception 'Destination required'; end if;
  select * into v_row from public.rr_fg_despatch_v787
  where id=p_despatch_id for update;
  if not found then raise exception 'Challan not found'; end if;
  if v_row.status not in ('IN_TRANSIT','PART_RECEIVED') then
    raise exception 'Destination can be set only on pending receive challan';
  end if;
  update public.rr_fg_despatch_v787 set destination=v_dest where id=p_despatch_id;
  return jsonb_build_object(
    'despatch_id',p_despatch_id,'destination',v_dest,'status',v_row.status,
    'performed_by',auth.uid(),'act_as_worker_id',v_access->>'worker_id'
  );
end $$;

create or replace function public.rr_fg_receive_accept_v9361(
  p_despatch_id uuid,
  p_groups jsonb default '[]'::jsonb,
  p_accept_as text default 'RECEIVER',
  p_remarks text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  d public.rr_fg_despatch_v787%rowtype;
  a public.rr_fg_despatch_acceptance_v9356%rowtype;
  c public.rr_fg_despatch_custody_v9361%rowtype;
  v_access jsonb;
  x jsonb;
  gid uuid;
  rq int;
  rb int;
  v_expected_qty int;
  v_expected_boxes int;
  v_group_count int;
  v_changed boolean:=false;
  v_mismatch boolean:=false;
  v_already boolean:=false;
  total_received int;
  total_expected int;
begin
  perform public.rr_fg_assert_user_v787();
  select * into d from public.rr_fg_despatch_v787
  where id=p_despatch_id for update;
  if not found then raise exception 'Challan not found'; end if;
  select * into c from public.rr_fg_despatch_custody_v9361
  where despatch_id=p_despatch_id;
  if not found then raise exception 'Despatch Line Man mapping missing'; end if;
  v_access:=public.rr_fg_effective_despatch_access_v335(p_despatch_id);

  insert into public.rr_fg_despatch_acceptance_v9356(despatch_id)
  values(p_despatch_id) on conflict do nothing;
  select * into a from public.rr_fg_despatch_acceptance_v9356
  where despatch_id=p_despatch_id for update;
  if a.finalized then
    return jsonb_build_object(
      'finalized',true,'already_finalized',true,'duplicate_blocked',true,
      'challan_no',d.challan_no
    );
  end if;

  if upper(p_accept_as)='RECEIVER' then
    if not coalesce((v_access->>'can_receive')::boolean,false) then
      raise exception 'Effective Store/Sales/Admin authorization required';
    end if;
    if jsonb_typeof(coalesce(p_groups,'[]'::jsonb))<>'array' then
      raise exception 'Receive groups array required';
    end if;
    select count(*) into v_group_count
    from public.rr_fg_despatch_receive_groups_v9356
    where despatch_id=p_despatch_id;
    if jsonb_array_length(coalesce(p_groups,'[]'::jsonb))<>v_group_count then
      raise exception 'Every challan group must be verified exactly once';
    end if;

    for x in select * from jsonb_array_elements(coalesce(p_groups,'[]'::jsonb)) loop
      gid:=nullif(x->>'id','')::uuid;
      rq:=nullif(x->>'received_qty','')::int;
      rb:=nullif(x->>'received_box_count','')::int;
      if gid is null or rq is null or rb is null then
        raise exception 'Group, Received Box and Received PCS required';
      end if;
      if rq<0 then raise exception 'Received PCS cannot be negative'; end if;
      if rb<0 then raise exception 'Received Box cannot be negative'; end if;
      select expected_qty,box_count into v_expected_qty,v_expected_boxes
      from public.rr_fg_despatch_receive_groups_v9356
      where id=gid and despatch_id=p_despatch_id;
      if not found then raise exception 'Invalid receive group'; end if;
      if rq<>v_expected_qty or rb<>v_expected_boxes then v_mismatch:=true; end if;
      update public.rr_fg_despatch_receive_groups_v9356 g
      set received_qty=rq,received_box_count=rb,updated_at=now()
      where g.id=gid and g.despatch_id=p_despatch_id
        and (g.received_qty is distinct from rq or g.received_box_count is distinct from rb);
      if found then v_changed:=true; end if;
    end loop;
    if v_mismatch and nullif(trim(coalesce(p_remarks,'')),'') is null then
      raise exception 'Short / Excess reason mandatory';
    end if;
    if exists(
      select 1 from public.rr_fg_despatch_receive_groups_v9356
      where despatch_id=p_despatch_id
        and (received_qty is null or received_box_count is null)
    ) then raise exception 'Har group ka Box / PCS Received fill karein'; end if;

    v_already:=a.receiver_accepted and not v_changed;
    if not v_already then
      update public.rr_fg_despatch_acceptance_v9356
      set receiver_accepted=true,receiver_by=auth.uid(),receiver_at=now(),
          depositor_accepted=case when v_changed then false else depositor_accepted end,
          depositor_by=case when v_changed then null else depositor_by end,
          depositor_at=case when v_changed then null else depositor_at end,
          remarks=coalesce(nullif(trim(p_remarks),''),remarks),updated_at=now()
      where despatch_id=p_despatch_id;
    end if;
  elsif upper(p_accept_as)='DEPOSITOR' then
    if not coalesce((v_access->>'can_deposit')::boolean,false) then
      raise exception 'Selected Delivery Line Man or Super Admin must confirm handover';
    end if;
    if not a.receiver_accepted then raise exception 'Store receiver verification pending'; end if;
    if exists(
      select 1 from public.rr_fg_despatch_receive_groups_v9356
      where despatch_id=p_despatch_id
        and (received_qty is null or received_box_count is null)
    ) then raise exception 'Receiver Box / PCS entry pending'; end if;
    v_already:=a.depositor_accepted;
    if not v_already then
      update public.rr_fg_despatch_acceptance_v9356
      set depositor_accepted=true,depositor_by=auth.uid(),depositor_at=now(),
          remarks=coalesce(nullif(trim(p_remarks),''),remarks),updated_at=now()
      where despatch_id=p_despatch_id;
    end if;
  else
    raise exception 'Accept as RECEIVER or DEPOSITOR';
  end if;

  select * into a from public.rr_fg_despatch_acceptance_v9356
  where despatch_id=p_despatch_id for update;
  if a.receiver_accepted and a.depositor_accepted then
    select sum(expected_qty),sum(received_qty)
      into total_expected,total_received
    from public.rr_fg_despatch_receive_groups_v9356
    where despatch_id=p_despatch_id;
    insert into public.rr_fg_stock_ledger_v787(
      txn_type,ref_type,ref_id,lot_no,stock_type,location_code,
      qty_delta,rate,data_mode,meta
    )
    select 'STORE_RECEIVE','DESPATCH_GROUP_V9356',g.id,g.lot_no,g.stock_type,
      d.destination,g.received_qty,
      coalesce((
        select r.final_rate from public.rr_pack_rate_approval_v9340 r
        where r.data_mode=d.data_mode and r.lot_no=g.lot_no and r.status='APPROVED'
        order by r.approved_at desc nulls last,r.updated_at desc limit 1
      ),0),d.data_mode,
      jsonb_build_object(
        'challan_no',d.challan_no,'expected_qty',g.expected_qty,
        'received_qty',g.received_qty,'short_excess',g.received_qty-g.expected_qty,
        'box_from',g.box_from,'box_to',g.box_to,'box_count',g.box_count,
        'received_box_count',g.received_box_count,'line_man',c.line_man_name,
        'packer',c.packer_name,'performed_by',auth.uid(),
        'act_as_worker_id',v_access->>'worker_id'
      )
    from public.rr_fg_despatch_receive_groups_v9356 g
    where g.despatch_id=p_despatch_id
      and not exists(
        select 1 from public.rr_fg_stock_ledger_v787 s
        where s.ref_type='DESPATCH_GROUP_V9356' and s.ref_id=g.id
      );
    update public.rr_fg_despatch_boxes_v787 set accepted=true
    where despatch_id=p_despatch_id;
    update public.rr_fg_boxes_v787 b
    set status='STORE_AVAILABLE',location_code=d.destination
    where b.id in (
      select unnest(g.box_ids)
      from public.rr_fg_despatch_receive_groups_v9356 g
      where g.despatch_id=p_despatch_id
    );
    update public.rr_fg_despatch_v787
    set status='RECEIVED',received_by=a.receiver_by,received_at=now(),
        receive_remarks=coalesce(nullif(trim(p_remarks),''),receive_remarks)
    where id=p_despatch_id;
    update public.rr_fg_despatch_acceptance_v9356
    set finalized=true,finalized_at=now(),updated_at=now()
    where despatch_id=p_despatch_id;
    return jsonb_build_object(
      'finalized',true,'already_finalized',false,'already_accepted',v_already,
      'duplicate_blocked',v_already,'challan_no',d.challan_no,
      'expected_qty',total_expected,'received_qty',total_received,
      'short_excess',total_received-total_expected,
      'line_man_name',c.line_man_name,'packer_name',c.packer_name,
      'performed_by',auth.uid(),'act_as_worker_id',v_access->>'worker_id'
    );
  end if;
  return jsonb_build_object(
    'finalized',false,'already_accepted',v_already,'duplicate_blocked',v_already,
    'receiver_accepted',a.receiver_accepted,
    'depositor_accepted',a.depositor_accepted,
    'line_man_name',c.line_man_name,'performed_by',auth.uid(),
    'act_as_worker_id',v_access->>'worker_id'
  );
end $$;

-- Rollback-only proof. It exercises real partial/full writers, App/Chat
-- projections and both receive acknowledgements without retaining a challan,
-- stock posting, or fixture change.
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

revoke all on function public.rr_fg_despatch_action_context_v335(uuid) from public,anon;
revoke all on function public.rr_fg_despatch_ready_boxes_v335(text,text) from public,anon;
revoke all on function public.rr_fg_create_despatch_chat_v335(text,jsonb,uuid,text,text,uuid,text) from public,anon;
revoke all on function public.rr_fg_despatch_line_men_v9361() from public,anon;
revoke all on function public.rr_fg_set_receive_destination_v9397(uuid,text) from public,anon;
revoke all on function public.rr_fg_receive_accept_v9361(uuid,jsonb,text,text) from public,anon;
revoke all on function public.rr_test_checkpoint7_despatch_receive_v335() from public,anon;
revoke all on function public.rr_fg_create_despatch_lot_v9361(text,uuid,text,text,text) from public,anon;
revoke all on function public.rr_fg_create_despatch_v7981(jsonb,text,text,text) from public,anon;
revoke all on function public.rr_fg_receive_pending_v9361(text) from public,anon;

grant execute on function public.rr_fg_despatch_action_context_v335(uuid) to authenticated,service_role;
grant execute on function public.rr_fg_despatch_ready_boxes_v335(text,text) to authenticated,service_role;
grant execute on function public.rr_fg_create_despatch_chat_v335(text,jsonb,uuid,text,text,uuid,text) to authenticated,service_role;
grant execute on function public.rr_fg_despatch_line_men_v9361() to authenticated,service_role;
grant execute on function public.rr_fg_set_receive_destination_v9397(uuid,text) to authenticated,service_role;
grant execute on function public.rr_fg_receive_accept_v9361(uuid,jsonb,text,text) to authenticated,service_role;
grant execute on function public.rr_test_checkpoint7_despatch_receive_v335() to authenticated,service_role;
grant execute on function public.rr_fg_create_despatch_lot_v9361(text,uuid,text,text,text) to authenticated,service_role;
grant execute on function public.rr_fg_create_despatch_v7981(jsonb,text,text,text) to authenticated,service_role;
grant execute on function public.rr_fg_receive_pending_v9361(text) to authenticated,service_role;

commit;
