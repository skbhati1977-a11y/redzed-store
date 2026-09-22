-- TEST71 V618: make CB Department WORKING a truthful aggregate of the
-- canonical Product Master decision view and V615 Cutting child lifecycle.
-- Existing named CB rows are evidence only; this migration changes shared
-- validation/projection rules and never patches a named business record.
begin;

do $patch$
declare
  d text;
  anchor text := $old$  if reg_rate is null or reg_rate<=0 then raise exception 'Regular Cloth Rate required.'; end if;
  reg_amount:=coalesce(reg_amount,round(reg_qty*reg_rate,2));$old$;
  replacement text := $new$  if reg_rate is null or reg_rate<=0 then raise exception 'Regular Cloth Rate required.'; end if;
  if p_confirm and (
    nullif(trim(reg->>'vendor'),'') is null
    or nullif(trim(reg->>'fabric_name'),'') is null
    or nullif(trim(reg->>'bill_no'),'') is null
    or nullif(reg->>'bill_date','') is null
    or nullif(reg->>'category_id','') is null
    or not exists(
      select 1 from public.rr_material_categories mc
      where mc.id=(reg->>'category_id')::uuid
        and mc.is_active
        and lower(mc.category_code)='regular-cloth'
    )
  ) then
    raise exception 'Regular Cloth Supplier, Fabric, Bill, Date and canonical Material mapping are required before Save & Confirm.';
  end if;
  reg_amount:=coalesce(reg_amount,round(reg_qty*reg_rate,2));$new$;
begin
  select replace(pg_get_functiondef(
    'public.rr_cb_department_save_v600(uuid,uuid,boolean,jsonb)'::regprocedure
  ),chr(13),'') into d;
  if position('Regular Cloth Supplier, Fabric, Bill, Date and canonical Material mapping are required before Save & Confirm.' in d)>0 then
    return;
  end if;
  if position(anchor in d)=0 then
    raise exception 'V618 refused: canonical CB save validation signature changed';
  end if;
  execute replace(d,anchor,replacement);
end
$patch$;

create or replace function public.rr_cb_reconcile_department_states_v618()
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_rows integer:=0;
begin
  with unit_truth as(
    select u.purchase_id,public.rr_cutting_child_lifecycle_v615(u.id) lifecycle
    from public.rr_cb_units u
    where coalesce(u.is_final,true)
  ), truth as(
    select fp.id,
      case
        when count(u.lifecycle) filter(where u.lifecycle->>'state'<>'NOT_AVAILABLE')=0 then 'CLOSE'
        when count(u.lifecycle) filter(where u.lifecycle->>'state'='RELEASED')
          =count(u.lifecycle) filter(where u.lifecycle->>'state'<>'NOT_AVAILABLE') then 'CLOSE'
        when count(u.lifecycle) filter(where u.lifecycle->>'state'='ART_DUE')>0 then 'WORKING'
        else 'CLOSE'
      end desired_state
    from public.rr_fabric_purchases fp
    left join unit_truth u on u.purchase_id=fp.id
    where upper(coalesce(fp.operation_status,'ACTIVE'))='ACTIVE'
      and fp.cb_department_state<>'OPEN'
    group by fp.id
  )
  update public.rr_fabric_purchases fp
  set cb_department_state=t.desired_state,updated_at=fp.updated_at
  from truth t
  where fp.id=t.id and fp.cb_department_state is distinct from t.desired_state;
  get diagnostics v_rows=row_count;
  return jsonb_build_object('states_reconciled',v_rows);
end
$function$;

revoke all on function public.rr_cb_reconcile_department_states_v618() from public,anon,authenticated;
grant execute on function public.rr_cb_reconcile_department_states_v618() to service_role;

-- Detail/edit hydration must expose the same CB Department lifecycle as the
-- queue projection.  Cutting lots are a downstream dimension and must not
-- keep an Art-complete CB in WORKING.
create or replace function public.rr_cb_department_detail_v600(p_cb_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $function$
declare
  v jsonb;
begin
  perform public.rr_cb_department_assert_authority_v600();
  select jsonb_build_object(
    'cb_id',fp.id,'cb_no',fp.cb_no,'state',fp.cb_department_state,
    'division_count',fp.division_count,'colour_count',fp.colour_count,'remarks',fp.notes,
    'colours',coalesce((
      select jsonb_agg(jsonb_build_object(
        'index',c.col_no,'name',c.colour_name,'image_url',c.image_url,
        'media_id',c.media_id,'confirmed',c.is_confirmed
      ) order by c.col_no)
      from public.rr_cb_colours c where c.cb_id=fp.id
    ),'[]'::jsonb),
    'entries',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',p.id,'client_key',p.client_key,'category_id',p.material_category_id,
        'category_name',mc.category_name,'category_code',mc.category_code,
        'vendor',p.vendor_name,'bill_no',p.vendor_bill_no,'bill_date',p.bill_date,
        'fabric_name',p.fabric_name,'qty',p.quantity,'rate',p.rate,'amount',p.amount,
        'state',p.requirement_state,'unit',p.unit,'cutting_blocking',p.cutting_blocking,
        'entry_notes',p.entry_notes,
        'rolls',coalesce((
          select jsonb_agg(jsonb_build_object(
            'colour_index',c.col_no,'roll_no',r.roll_no,'qty',r.quantity
          ) order by c.col_no,r.roll_no)
          from public.rr_cb_purchase_rolls r
          join public.rr_cb_colours c on c.id=r.cb_colour_id
          where r.purchase_entry_id=p.id
        ),'[]'::jsonb)
      ) order by p.created_at)
      from public.rr_cb_purchase_entries p
      join public.rr_material_categories mc on mc.id=p.material_category_id
      where p.cb_id=fp.id
    ),'[]'::jsonb)
  ) into v
  from public.rr_fabric_purchases fp
  where fp.id=p_cb_id;

  if v is null then raise exception 'CB not found.'; end if;
  return v;
end
$function$;

revoke all on function public.rr_cb_department_detail_v600(uuid) from public,anon;
grant execute on function public.rr_cb_department_detail_v600(uuid) to authenticated;

do $patch$
declare
  d text;
  anchor text := $old$  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'sticker_master_ids',coalesce(p_sticker_master_ids,'{}'::uuid[]),$old$;
  replacement text := $new$  -- CB Department work ends when the final required Product Master decision
  -- completes. Cutting HOLD/READY remains a separate downstream dimension.
  perform public.rr_cb_reconcile_department_states_v618();

  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'sticker_master_ids',coalesce(p_sticker_master_ids,'{}'::uuid[]),$new$;
begin
  select replace(pg_get_functiondef(
    'public.rr_pm_save_decision_bundle_v804(uuid,uuid,text,uuid[],text,uuid[],text,uuid[],text)'::regprocedure
  ),chr(13),'') into d;
  if position('CB Department work ends when the final required Product Master decision' in d)>0 then
    return;
  end if;
  if position(anchor in d)=0 then
    raise exception 'V618 refused: canonical Product Master save signature changed';
  end if;
  execute replace(d,anchor,replacement);
end
$patch$;

create or replace function public.rr_cb_department_cards_v600(
  p_state text default null,
  p_search text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $function$
declare
  cards jsonb;
  ident jsonb:=public.rr_upm_effective_identity_v200();
  worker uuid:=public.rr_upm_current_worker_id_v9112();
  role_code text;
begin
  perform public.rr_assert_active_user_v1();
  role_code:=upper(coalesce(ident->>'role_code',ident->>'resolved_role',''));
  if role_code not in('OWNER','SUPER_ADMIN','ADMIN') and not exists(
    select 1 from public.rr_real_chat_department_membership_v70 m
    where m.worker_id=worker and m.is_active
      and public.rr_real_chat_canonical_department_v83(m.department_code)='PURCHASE'
  ) then
    raise exception 'CB Department membership required.' using errcode='42501';
  end if;

  with unit_truth as(
    select u.purchase_id,u.id unit_id,u.cb_code,u.division_index,u.combo_mode,
      u.is_cutting_enabled,u.operation_status,d.art_status,d.print_status,
      d.sticker_status,d.metal_id_status,d.all_decisions_complete,
      public.rr_cutting_child_lifecycle_v615(u.id) lifecycle
    from public.rr_cb_units u
    left join public.rr_pm_decision_status_v802 d on d.cb_unit_id=u.id
    where coalesce(u.is_final,true)
  ), rollup as(
    select purchase_id,
      count(*)::integer child_count,
      count(*) filter(where lifecycle->>'state'<>'NOT_AVAILABLE')::integer available_count,
      count(*) filter(where lifecycle->>'state'='NOT_AVAILABLE')::integer unavailable_count,
      count(*) filter(where lifecycle->>'state'='ART_DUE')::integer art_due_count,
      count(*) filter(where lifecycle->>'state'='CUTTING_HOLD')::integer hold_count,
      count(*) filter(where lifecycle->>'state'='READY_FOR_CUTTING')::integer ready_count,
      count(*) filter(where lifecycle->>'state'='RELEASED')::integer released_count,
      count(*) filter(where lifecycle->>'state'<>'NOT_AVAILABLE' and coalesce(all_decisions_complete,false))::integer decision_complete_count
    from unit_truth group by purchase_id
  ), base as(
    select fp.*,coalesce(x.child_count,0) child_count,
      coalesce(x.available_count,0) available_count,
      coalesce(x.unavailable_count,0) unavailable_count,
      coalesce(x.art_due_count,0) art_due_count,
      coalesce(x.hold_count,0) hold_count,
      coalesce(x.ready_count,0) ready_count,
      coalesce(x.released_count,0) released_count,
      coalesce(x.decision_complete_count,0) decision_complete_count,
      case
        when fp.cb_department_state='OPEN' then 'OPEN'
        when coalesce(x.available_count,0)=0 then 'CLOSE'
        when coalesce(x.released_count,0)=coalesce(x.available_count,0) then 'CLOSE'
        when coalesce(x.art_due_count,0)>0 then 'WORKING'
        else 'CLOSE'
      end resolved_state,
      case
        when fp.cb_department_state<>'OPEN' and coalesce(x.available_count,0)=0
          then 'INCOMPLETE_LEGACY_HISTORY'
        when fp.cb_department_state<>'OPEN'
          and coalesce(x.available_count,0)>0
          and coalesce(x.released_count,0)=coalesce(x.available_count,0)
          then 'RELEASED_HISTORY'
        else null
      end history_reason
    from public.rr_fabric_purchases fp
    left join rollup x on x.purchase_id=fp.id
    where upper(coalesce(fp.operation_status,'ACTIVE'))='ACTIVE'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'event_key','CB_DEPARTMENT:'||b.id,
    'source_module','CB_DEPARTMENT',
    'card_type','CB_DEPARTMENT',
    'cb_id',b.id,
    'cb_no',b.cb_no,
    'lot_no',b.cb_no,
    'department_code','PURCHASE',
    'department_name','CB Department',
    'source_status',b.resolved_state,
    'canonical_state',b.resolved_state,
    'history_reason',b.history_reason,
    'division_count',b.division_count,
    'colour_count',b.colour_count,
    'quantity',coalesce(r.quantity,b.total_weight),
    'quantity_unit',coalesce(nullif(r.unit,''),'KG'),
    'supplier',r.vendor_name,
    'fabric_name',r.fabric_name,
    'bill_no',r.vendor_bill_no,
    'bill_date',r.bill_date,
    'roll_count',coalesce((select count(*) from public.rr_cb_purchase_rolls z where z.purchase_entry_id=r.id),0),
    'amount',r.amount,
    'actual_rate',r.rate,
    'pending_material_count',(select count(*) from public.rr_cb_purchase_entries p where p.cb_id=b.id and upper(coalesce(p.requirement_state,''))='DUE'),
    'child_count',b.child_count,
    'available_child_count',b.available_count,
    'unavailable_child_count',b.unavailable_count,
    'decision_complete_count',b.decision_complete_count,
    'art_due_count',b.art_due_count,
    'cutting_hold_count',b.hold_count,
    'cutting_ready_count',b.ready_count,
    'released_child_count',b.released_count,
    'materials',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',p.id,'name',mc.category_name,'state',p.requirement_state,
        'qty',p.quantity,'unit',p.unit,'cutting_blocking',p.cutting_blocking
      ) order by mc.sort_order,mc.category_name)
      from public.rr_cb_purchase_entries p
      join public.rr_material_categories mc on mc.id=p.material_category_id
      where p.cb_id=b.id
        and lower(coalesce(mc.category_code,''))<>'regular-cloth'
        and lower(coalesce(p.entry_notes,''))<>'regular cloth'
    ),'[]'::jsonb),
    'cb_children',coalesce((
      select jsonb_agg(jsonb_build_object(
        'cb_unit_id',u.unit_id,'cb_code',u.cb_code,'division_index',u.division_index,
        'state',u.lifecycle->>'state','canonical_state',u.lifecycle->>'canonical_state',
        'art_status',coalesce(u.art_status,'ART_DUE'),
        'print_status',coalesce(u.print_status,'WAITING_FOR_ART'),
        'sticker_status',coalesce(u.sticker_status,'WAITING_FOR_ART'),
        'metal_id_status',coalesce(u.metal_id_status,'WAITING_FOR_ART'),
        'all_decisions_complete',coalesce(u.all_decisions_complete,false),
        'combo_mode',coalesce(u.combo_mode,'single'),
        'material_due_count',coalesce((u.lifecycle->>'material_due_count')::integer,0),
        'lots',coalesce(u.lifecycle->'lots','[]'::jsonb)
      ) order by u.division_index,u.cb_code)
      from unit_truth u where u.purchase_id=b.id
    ),'[]'::jsonb),
    'art_status',case
      when b.available_count=0 then 'NOT AVAILABLE'
      when b.decision_complete_count=b.available_count then 'COMPLETE'
      when b.decision_complete_count>0 then b.decision_complete_count||'/'||b.available_count||' COMPLETE'
      else 'DUE'
    end,
    'art_combo_status',case when exists(
      select 1 from unit_truth u where u.purchase_id=b.id and coalesce(u.combo_mode,'single')<>'single'
    ) then 'MULTI / COMBO' else 'SINGLE' end,
    'art_actions',coalesce((
      select jsonb_agg(jsonb_build_object(
        'code','ART_DECISION','label',case
          when coalesce(u.art_status,'ART_DUE')='ART_DUE' then 'ART DECISION · '||u.cb_code
          when u.print_status='PRINT_DUE' then 'PRINT DECISION · '||u.cb_code
          when u.sticker_status='STICKER_DUE' then 'STICKER DECISION · '||u.cb_code
          when u.metal_id_status='METAL_ID_DUE' then 'METAL ID DECISION · '||u.cb_code
          else 'ART / COMBO DECISION · '||u.cb_code end,
        'cb_unit_id',u.unit_id,'cb_code',u.cb_code,
        'href','real-art-decide-master.html?cb_unit_id='||u.unit_id||'&from=CB_DEPARTMENT',
        'engine','rr_pm_save_decision_bundle_v804',
        'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN')
      ) order by u.division_index,u.cb_code)
      from unit_truth u where u.purchase_id=b.id and u.lifecycle->>'state'='ART_DUE'
    ),'[]'::jsonb),
    'next_actions',coalesce((
      select jsonb_agg(jsonb_build_object(
        'code',case when u.lifecycle->>'state'='ART_DUE' then 'ART_DECISION' else 'CUTTING_RELEASE' end,
        'label',case
          when u.lifecycle->>'state'='ART_DUE' and coalesce(u.art_status,'ART_DUE')='ART_DUE' then 'ART DECISION · '||u.cb_code
          when u.lifecycle->>'state'='ART_DUE' and u.print_status='PRINT_DUE' then 'PRINT DECISION · '||u.cb_code
          when u.lifecycle->>'state'='ART_DUE' and u.sticker_status='STICKER_DUE' then 'STICKER DECISION · '||u.cb_code
          when u.lifecycle->>'state'='ART_DUE' and u.metal_id_status='METAL_ID_DUE' then 'METAL ID DECISION · '||u.cb_code
          when u.lifecycle->>'state'='ART_DUE' then 'ART / COMBO DECISION · '||u.cb_code
          else 'CONTINUE IN CUTTING · '||u.cb_code end,
        'cb_unit_id',u.unit_id,'cb_code',u.cb_code,
        'href',case when u.lifecycle->>'state'='ART_DUE'
          then 'real-art-decide-master.html?cb_unit_id='||u.unit_id||'&from=CB_DEPARTMENT'
          else 'real-cutting-master.html?cb_unit_id='||u.unit_id end,
        'engine',case when u.lifecycle->>'state'='ART_DUE'
          then 'rr_pm_save_decision_bundle_v804' else 'EXISTING_CUTTING_RELEASE_CHAIN' end,
        'allowed_roles',case when u.lifecycle->>'state'='ART_DUE'
          then jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN')
          else jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER') end
      ) order by u.division_index,u.cb_code)
      from unit_truth u
      where u.purchase_id=b.id and u.lifecycle->>'state' in('ART_DUE','READY_FOR_CUTTING')
    ),'[]'::jsonb),
    'message',case
      when b.resolved_state='OPEN' then 'CB created · Final review pending'
      when b.history_reason='INCOMPLETE_LEGACY_HISTORY' then 'INCOMPLETE LEGACY CB · READ-ONLY HISTORY'
      when b.resolved_state='CLOSE' and b.released_count=b.available_count then 'SENT TO CUTTING'
      when b.art_due_count>0 then b.art_due_count||' D CARD'||case when b.art_due_count=1 then '' else 'S' end||' DECISION DUE'
      when b.hold_count>0 then 'CB COMPLETE · CUTTING HOLD · '||(select count(*) from public.rr_cb_purchase_entries p where p.cb_id=b.id and upper(coalesce(p.requirement_state,''))='DUE')||' MATERIAL DUE'
      else 'CB COMPLETE · READY FOR CUTTING · '||b.ready_count||' D CARD'||case when b.ready_count=1 then '' else 'S' end||case when b.released_count>0 then ' · '||b.released_count||' RELEASED' else '' end
    end,
    'event_at',b.updated_at,
    'edit_href','real-cb-new-v9130-fix2.html?cb_id='||b.id||'&from=CB_DEPARTMENT',
    'read_only',b.resolved_state='CLOSE'
  ) order by b.updated_at desc,b.cb_no),'[]'::jsonb) into cards
  from base b
  left join lateral(
    select p.* from public.rr_cb_purchase_entries p
    left join public.rr_material_categories mc on mc.id=p.material_category_id
    where p.cb_id=b.id and (
      lower(coalesce(mc.category_code,''))='regular-cloth'
      or lower(coalesce(p.entry_notes,''))='regular cloth'
    )
    order by case when lower(coalesce(mc.category_code,''))='regular-cloth' then 0 else 1 end,p.created_at
    limit 1
  ) r on true
  where (p_state is null or upper(p_state)=b.resolved_state)
    and (
      nullif(trim(coalesce(p_search,'')),'') is null
      or b.cb_no ilike '%'||trim(p_search)||'%'
      or coalesce(r.fabric_name,'') ilike '%'||trim(p_search)||'%'
      or exists(select 1 from unit_truth u where u.purchase_id=b.id and u.cb_code ilike '%'||trim(p_search)||'%')
    );

  return jsonb_build_object(
    'cards',cards,
    'department_code','PURCHASE',
    'department_name','CB Department',
    'projection_version','V618'
  );
end
$function$;

revoke all on function public.rr_cb_department_cards_v600(text,text) from public,anon;
grant execute on function public.rr_cb_department_cards_v600(text,text) to authenticated;

comment on function public.rr_cb_department_cards_v600(text,text) is
  'TEST71 V618 truthful CB Department projection: category-based Regular Cloth hydration, per-child Product Master/Cutting lifecycle, invalid legacy history, and canonical next actions.';

create or replace function public.rr_real_chat_reconcile_cb_parent_v618()
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_rows integer:=0;
begin
  with unit_truth as(
    select u.purchase_id,u.id unit_id,u.cb_code,u.division_index,
      d.art_status,d.print_status,d.sticker_status,d.metal_id_status,
      public.rr_cutting_child_lifecycle_v615(u.id) lifecycle
    from public.rr_cb_units u
    left join public.rr_pm_decision_status_v802 d on d.cb_unit_id=u.id
    where coalesce(u.is_final,true)
  ), parent_truth as(
    select fp.id purchase_id,
      case
        when fp.cb_department_state='OPEN' then 'OPEN'
        when count(u.unit_id) filter(where u.lifecycle->>'state'<>'NOT_AVAILABLE')=0 then 'CLOSE'
        when count(u.unit_id) filter(where u.lifecycle->>'state'='RELEASED')
          =count(u.unit_id) filter(where u.lifecycle->>'state'<>'NOT_AVAILABLE') then 'CLOSE'
        when count(u.unit_id) filter(where u.lifecycle->>'state'='ART_DUE')>0 then 'WORKING'
        else 'CLOSE'
      end canonical_state,
      count(u.unit_id) filter(where u.lifecycle->>'state'<>'NOT_AVAILABLE')::integer available_count,
      count(u.unit_id) filter(where u.lifecycle->>'state'='ART_DUE')::integer art_due_count,
      count(u.unit_id) filter(where u.lifecycle->>'state'='CUTTING_HOLD')::integer hold_count,
      count(u.unit_id) filter(where u.lifecycle->>'state'='READY_FOR_CUTTING')::integer ready_count,
      count(u.unit_id) filter(where u.lifecycle->>'state'='RELEASED')::integer released_count,
      coalesce(jsonb_agg(jsonb_build_object(
        'cb_unit_id',u.unit_id,'cb_code',u.cb_code,'state',u.lifecycle->>'state',
        'canonical_state',u.lifecycle->>'canonical_state',
        'material_due_count',coalesce((u.lifecycle->>'material_due_count')::integer,0),
        'lots',coalesce(u.lifecycle->'lots','[]'::jsonb)
      ) order by u.division_index,u.cb_code) filter(where u.unit_id is not null),'[]'::jsonb) children,
      coalesce(jsonb_agg(jsonb_build_object(
        'code',case when u.lifecycle->>'state'='ART_DUE' then 'ART_DECISION' else 'CUTTING_RELEASE' end,
        'label',case when u.lifecycle->>'state'='ART_DUE' then 'ART / CRAFTING DECISION · '||u.cb_code else 'CONTINUE IN CUTTING · '||u.cb_code end,
        'href',case when u.lifecycle->>'state'='ART_DUE' then 'real-art-decide-master.html?cb_unit_id='||u.unit_id||'&from=CB_DEPARTMENT' else 'real-cutting-master.html?cb_unit_id='||u.unit_id end,
        'engine',case when u.lifecycle->>'state'='ART_DUE' then 'rr_pm_save_decision_bundle_v804' else 'EXISTING_CUTTING_RELEASE_CHAIN' end,
        'cb_unit_id',u.unit_id,
        'allowed_roles',case when u.lifecycle->>'state'='ART_DUE' then jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN') else jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER') end
      ) order by u.division_index,u.cb_code) filter(where u.lifecycle->>'state' in('ART_DUE','READY_FOR_CUTTING')),'[]'::jsonb) actions
    from public.rr_fabric_purchases fp
    left join unit_truth u on u.purchase_id=fp.id
    where upper(coalesce(fp.operation_status,'ACTIVE'))='ACTIVE'
    group by fp.id,fp.cb_department_state
  ), prepared as(
    select p.*,p.actions->0 first_action,
      case
        when p.canonical_state='OPEN' then 'CB created · Final review pending'
        when p.available_count=0 then 'INCOMPLETE LEGACY CB · READ-ONLY HISTORY'
        when p.canonical_state='CLOSE' and p.released_count=p.available_count then 'SENT TO CUTTING'
        when p.art_due_count>0 then p.art_due_count||' D CARD DECISION DUE'
        when p.hold_count>0 then 'CB COMPLETE · CUTTING HOLD · MATERIAL DUE'
        else 'CB COMPLETE · READY FOR CUTTING · '||p.ready_count||' D CARD'||case when p.ready_count=1 then '' else 'S' end
      end projection_message
    from parent_truth p
  )
  update public.rr_real_chat_message_bridge_v70 b
  set personal_payload=(coalesce(b.personal_payload,'{}'::jsonb)
        -'next_actions'-'cb_children'-'action_href'-'action_engine'-'canonical_state'-'message')
        ||jsonb_build_object('canonical_state',p.canonical_state,'cb_children',p.children,
          'next_actions',p.actions,'message',p.projection_message,
          'projection_version','V618','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER'))
        ||case when p.first_action is null then '{}'::jsonb else jsonb_build_object(
          'action_href',p.first_action->>'href','action_engine',p.first_action->>'engine') end,
      group_payload=(coalesce(b.group_payload,'{}'::jsonb)
        -'next_actions'-'cb_children'-'action_href'-'action_engine'-'canonical_state'-'message')
        ||jsonb_build_object('canonical_state',p.canonical_state,'cb_children',p.children,
          'next_actions',p.actions,'message',p.projection_message,
          'projection_version','V618','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER'))
        ||case when p.first_action is null then '{}'::jsonb else jsonb_build_object(
          'action_href',p.first_action->>'href','action_engine',p.first_action->>'engine') end,
      action_code=p.first_action->>'code',
      action_label=p.first_action->>'label',
      deep_link=case when p.first_action is null then b.deep_link else p.first_action->>'href' end
  from prepared p
  where b.archived_at is null
    and b.source_module='CB_PURCHASE'
    and b.source_event_type='CREATE_CB_SUCCEEDED'
    and b.source_record_id=p.purchase_id::text;
  get diagnostics v_rows=row_count;

  return jsonb_build_object(
    'parents_reconciled',v_rows,
    'invalid_active_parent_projection',(select count(*) from public.rr_real_chat_message_bridge_v70 b
      join public.rr_fabric_purchases fp on fp.id::text=b.source_record_id
      where b.archived_at is null and b.source_module='CB_PURCHASE'
        and b.source_event_type='CREATE_CB_SUCCEEDED'
        and b.group_payload->>'projection_version'='V618'
        and b.group_payload->>'canonical_state'='WORKING'
        and not exists(select 1 from public.rr_cb_units u
          where u.purchase_id=fp.id and coalesce(u.is_final,true) and coalesce(u.is_cutting_enabled,true)))
  );
end
$function$;

create or replace function public.rr_real_chat_cb_parent_trigger_v618()
returns trigger
language plpgsql
security definer
set search_path='public'
as $function$
begin
  if pg_trigger_depth()>1 then return null; end if;
  perform public.rr_cb_reconcile_department_states_v618();
  perform public.rr_real_chat_reconcile_cb_parent_v618();
  return null;
exception when others then
  raise warning 'V618 CB parent reconciliation deferred: %',sqlerrm;
  return null;
end
$function$;

do $triggers$
declare t text;
begin
  foreach t in array array[
    'rr_fabric_purchases','rr_cb_units','rr_cb_art_assignments','rr_cb_print_assignments',
    'rr_cb_sticker_assignments','rr_cb_metal_id_assignments_v801','rr_cb_purchase_entries',
    'rr_cutting_lots_v3','rr_production_lots','rr_upm_lot_registry'
  ] loop
    execute format('drop trigger if exists zzzzzzzzzz_rr_cb_parent_v618 on public.%I',t);
    execute format('create trigger zzzzzzzzzz_rr_cb_parent_v618 after insert or update or delete on public.%I for each statement execute function public.rr_real_chat_cb_parent_trigger_v618()',t);
  end loop;
end
$triggers$;

revoke all on function public.rr_real_chat_reconcile_cb_parent_v618() from public,anon,authenticated;
revoke all on function public.rr_real_chat_cb_parent_trigger_v618() from public,anon;
grant execute on function public.rr_real_chat_reconcile_cb_parent_v618() to service_role;

do $patch$
declare
  d text;
  old_query text := $old$    select value into v_complete_card
    from jsonb_array_elements(public.rr_cb_department_cards_v600('WORKING',v_cb_no)->'cards')
    where value->>'cb_id'=v_cb::text;$old$;
  new_query text := $new$    select value into v_complete_card
    from jsonb_array_elements(public.rr_cb_department_cards_v600('CLOSE',v_cb_no)->'cards')
    where value->>'cb_id'=v_cb::text;$new$;
begin
  select replace(pg_get_functiondef('public.rr_test_cb_working_art_v611()'::regprocedure),chr(13),'') into d;
  if position(old_query in d)=0 then
    if position($already$rr_cb_department_cards_v600('CLOSE',v_cb_no)$already$ in d)>0 then return; end if;
    raise exception 'V618 refused: V611 proof completion query changed';
  end if;
  d:=replace(d,old_query,new_query);
  d:=replace(d,$old$(v_result->>'complete_message')='ART COMPLETE · MATERIAL DUE 1 · CUTTING HOLD'$old$,
    $new$(v_result->>'complete_message')='CB COMPLETE · CUTTING HOLD · 1 MATERIAL DUE'$new$);
  execute d;
end
$patch$;

create or replace function public.rr_test_cb_working_projection_v618()
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_regular uuid;
  v_art uuid;
  v_cb_no text:='TEST71-V618-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  v_payload jsonb;
  v_action uuid:=gen_random_uuid();
  v_draft jsonb;
  v_retry jsonb;
  v_confirm jsonb;
  v_open jsonb;
  v_initial jsonb;
  v_mid jsonb;
  v_ready jsonb;
  v_units uuid[];
  v_bridge jsonb;
  v_result jsonb;
  v_residue integer;
begin
  perform public.rr_cb_department_assert_authority_v600();
  select id into v_regular from public.rr_material_categories
  where lower(category_code)='regular-cloth' and is_active limit 1;
  select id into v_art from public.rr_art_master where is_active order by created_at,id limit 1;
  if v_regular is null or v_art is null then
    raise exception 'V618 proof requires Regular Cloth and one active Art.';
  end if;

  begin
    v_payload:=jsonb_build_object(
      'cb_no',v_cb_no,'division_count',2,'colour_count',1,
      'remarks','TEST71 V618 rollback-only WORKING projection proof',
      'colours',jsonb_build_array(jsonb_build_object(
        'index',1,'name','Colour 1','image_url','https://example.invalid/test71-v618.jpg','confirmed',true
      )),
      'regular',jsonb_build_object(
        'client_key',gen_random_uuid(),'category_id',v_regular,
        'vendor','TEST71 Supplier','bill_no','TEST71-V618','bill_date',current_date,
        'fabric_name','TEST71 Regular Cloth','qty',120,'rate',365,'amount',43800,
        'rolls',jsonb_build_array(
          jsonb_build_object('colour_index',1,'roll_no',1,'qty',60),
          jsonb_build_object('colour_index',1,'roll_no',2,'qty',60)
        )
      ),
      'materials','[]'::jsonb
    );

    v_draft:=public.rr_cb_department_save_v600(null,v_action,false,v_payload);
    v_retry:=public.rr_cb_department_save_v600(null,v_action,false,v_payload);
    select value into v_open
    from jsonb_array_elements(public.rr_cb_department_cards_v600('OPEN',v_cb_no)->'cards')
    where value->>'cb_id'=v_draft->>'cb_id';

    v_confirm:=public.rr_cb_department_save_v600((v_draft->>'cb_id')::uuid,gen_random_uuid(),true,v_payload);
    select array_agg(id order by division_index) into v_units
    from public.rr_cb_units
    where purchase_id=(v_draft->>'cb_id')::uuid and coalesce(is_final,true);

    select value into v_initial
    from jsonb_array_elements(public.rr_cb_department_cards_v600('WORKING',v_cb_no)->'cards')
    where value->>'cb_id'=v_draft->>'cb_id';

    perform public.rr_pm_save_decision_bundle_v804(v_units[1],v_art,'NA','{}'::uuid[],'NA','{}'::uuid[],'NA','{}'::uuid[],'TEST');
    perform public.rr_pm_save_decision_bundle_v804(v_units[1],v_art,'NA','{}'::uuid[],'NA','{}'::uuid[],'NA','{}'::uuid[],'TEST');
    select value into v_mid
    from jsonb_array_elements(public.rr_cb_department_cards_v600('WORKING',v_cb_no)->'cards')
    where value->>'cb_id'=v_draft->>'cb_id';

    perform public.rr_pm_save_decision_bundle_v804(v_units[2],v_art,'NA','{}'::uuid[],'NA','{}'::uuid[],'NA','{}'::uuid[],'TEST');
    perform public.rr_real_chat_reconcile_cb_parent_v618();
    select value into v_ready
    from jsonb_array_elements(public.rr_cb_department_cards_v600('CLOSE',v_cb_no)->'cards')
    where value->>'cb_id'=v_draft->>'cb_id';
    select group_payload into v_bridge
    from public.rr_real_chat_message_bridge_v70
    where archived_at is null and source_module='CB_PURCHASE'
      and source_event_type='CREATE_CB_SUCCEEDED'
      and source_record_id=v_draft->>'cb_id'
    order by sent_at desc limit 1;

    v_result:=jsonb_build_object(
      'draft',v_draft,'draft_retry',v_retry,'confirm',v_confirm,
      'open_state',v_open->>'source_status','open_cb_id',v_open->>'cb_id',
      'initial_art_status',v_initial->>'art_status',
      'initial_art_actions',jsonb_array_length(coalesce(v_initial->'art_actions','[]'::jsonb)),
      'mid_art_status',v_mid->>'art_status',
      'mid_art_actions',jsonb_array_length(coalesce(v_mid->'art_actions','[]'::jsonb)),
      'ready_art_status',v_ready->>'art_status',
      'ready_count',(v_ready->>'cutting_ready_count')::integer,
      'ready_actions',jsonb_array_length(coalesce(v_ready->'next_actions','[]'::jsonb)),
      'ready_message',v_ready->>'message',
      'supplier',v_ready->>'supplier','fabric_name',v_ready->>'fabric_name',
      'assignment_rows',(select count(*) from public.rr_cb_art_assignments where cb_id=any(v_units)),
      'bridge_state',v_bridge->>'canonical_state',
      'bridge_actions',jsonb_array_length(coalesce(v_bridge->'next_actions','[]'::jsonb))
    );
    raise exception using errcode='P6181',message='TEST71_CB_WORKING_PROJECTION_ROLLBACK';
  exception when sqlstate 'P6181' then
    if sqlerrm<>'TEST71_CB_WORKING_PROJECTION_ROLLBACK' then raise; end if;
  end;

  select count(*) into v_residue from public.rr_fabric_purchases where cb_no=v_cb_no;
  return v_result||jsonb_build_object(
    'exact_invariant',
      v_result->>'open_state'='OPEN'
      and v_result->>'open_cb_id'=v_result->'draft'->>'cb_id'
      and coalesce((v_result->'draft_retry'->>'duplicate_blocked')::boolean,false)
      and v_result->'confirm'->>'state'='WORKING'
      and v_result->>'initial_art_status'='DUE'
      and (v_result->>'initial_art_actions')::integer=2
      and v_result->>'mid_art_status'='1/2 COMPLETE'
      and (v_result->>'mid_art_actions')::integer=1
      and v_result->>'ready_art_status'='COMPLETE'
      and (v_result->>'ready_count')::integer=2
      and (v_result->>'ready_actions')::integer=2
      and v_result->>'ready_message'='CB COMPLETE · READY FOR CUTTING · 2 D CARDS'
      and v_result->>'supplier'='TEST71 Supplier'
      and v_result->>'fabric_name'='TEST71 Regular Cloth'
      and (v_result->>'assignment_rows')::integer=2
      and v_result->>'bridge_state'='CLOSE'
      and (v_result->>'bridge_actions')::integer=2,
    'rolled_back',v_residue=0,
    'fixture_residue',v_residue
  );
end
$function$;

alter function public.rr_test_cb_working_projection_v618() set statement_timeout='30s';
revoke all on function public.rr_test_cb_working_projection_v618() from public,anon;
grant execute on function public.rr_test_cb_working_projection_v618() to authenticated,service_role;

comment on function public.rr_test_cb_working_projection_v618() is
  'Rollback-only TEST71 proof: same CB OPEN-to-WORKING identity, per-child Art progress, retry-safe assignment, exact Cutting actions, Real Chat mirror, and zero fixture residue.';

select public.rr_cb_reconcile_department_states_v618();
select public.rr_real_chat_reconcile_cb_parent_v618();
notify pgrst,'reload schema';
commit;
