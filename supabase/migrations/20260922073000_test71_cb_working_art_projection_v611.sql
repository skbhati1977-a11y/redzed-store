-- TEST71 V611: make the CB WORKING projection follow the existing canonical
-- Product Master decision status and serialize retries through that engine.
-- No named CB/Lot/Card row is changed by this migration.
begin;

do $patch$
declare
  d text;
  old_sql text := $old$    select count(*) into due_blocking from public.rr_cb_purchase_entries
    where cb_id=cb and requirement_state='DUE' and cutting_blocking;
    if due_blocking>0 then raise exception 'Cutting-blocking DUE Material must be confirmed first.'; end if;
$old$;
begin
  select replace(pg_get_functiondef(
    'public.rr_cb_department_save_v600(uuid,uuid,boolean,jsonb)'::regprocedure
  ),chr(13),'') into d;
  if position(old_sql in d)=0 then
    if position('Cutting-blocking DUE Material must be confirmed first.' in d)=0 then
      return;
    end if;
    raise exception 'V611 refused: canonical CB confirmation gate signature changed';
  end if;
  execute replace(d,old_sql,
    '    -- DUE Materials block Cutting, not OPEN -> WORKING Art decisions.'||chr(10));
end
$patch$;

do $patch$
declare
  d text;
  anchor text := $old$begin
  if not public.rr_is_owner_or_admin() then raise exception 'Owner/Admin permission required.'; end if;$old$;
  replacement text := $new$begin
  if not public.rr_is_owner_or_admin() then raise exception 'Owner/Admin permission required.'; end if;
  if p_cb_unit_id is null then raise exception 'CB/D required.'; end if;
  -- Serialize double tap, reconnect and retry before any instruction or
  -- assignment row is created by the existing canonical V804 engine.
  perform pg_advisory_xact_lock(
    hashtextextended('RR_ART_DECISION:'||p_cb_unit_id::text,611)
  );$new$;
begin
  select replace(pg_get_functiondef(
    'public.rr_pm_save_decision_bundle_v804(uuid,uuid,text,uuid[],text,uuid[],text,uuid[],text)'::regprocedure
  ),chr(13),'') into d;
  if position('RR_ART_DECISION:' in d)>0 then
    return;
  end if;
  if position(anchor in d)=0 then
    raise exception 'V611 refused: canonical Art decision engine signature changed';
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

  with base as(
    select fp.*,
      case
        when fp.cb_department_state='OPEN' then 'OPEN'
        when exists(
          select 1 from public.rr_cb_units u
          where u.purchase_id=fp.id and coalesce(u.is_final,true)
        ) and not exists(
          select 1 from public.rr_cb_units u
          where u.purchase_id=fp.id and coalesce(u.is_final,true)
            and not exists(
              select 1 from public.rr_cutting_lots_v3 s
              where s.cb_unit_id=u.id
                and upper(coalesce(s.status,'')) not in('CANCELLED','CANCELED')
              union all
              select 1 from public.rr_production_lots m
              where m.cb_unit_id=u.id
                and upper(coalesce(m.status,'')) not in('CANCELLED','CANCELED')
            )
        ) then 'CLOSE'
        else 'WORKING'
      end resolved_state
    from public.rr_fabric_purchases fp
    where upper(coalesce(fp.operation_status,'ACTIVE'))='ACTIVE'
  ), projected as(
    select b.*,
      (select count(*) from public.rr_cb_purchase_entries p
        where p.cb_id=b.id and p.requirement_state='DUE')::integer as due_count,
      exists(
        select 1
        from public.rr_cb_units u
        left join public.rr_pm_decision_status_v802 d on d.cb_unit_id=u.id
        where u.purchase_id=b.id and coalesce(u.is_final,true)
          and not coalesce(d.all_decisions_complete,false)
      ) as art_due
    from base b
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
    'division_count',b.division_count,
    'colour_count',b.colour_count,
    'quantity',coalesce(r.quantity,b.total_weight),
    'quantity_unit','KG',
    'supplier',r.vendor_name,
    'fabric_name',r.fabric_name,
    'bill_no',r.vendor_bill_no,
    'bill_date',r.bill_date,
    'roll_count',coalesce((select count(*) from public.rr_cb_purchase_rolls z where z.purchase_entry_id=r.id),0),
    'amount',r.amount,
    'actual_rate',r.rate,
    'pending_material_count',b.due_count,
    'materials',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',p.id,'name',mc.category_name,'state',p.requirement_state,
        'qty',p.quantity,'unit',p.unit,'cutting_blocking',p.cutting_blocking
      ) order by mc.sort_order,mc.category_name)
      from public.rr_cb_purchase_entries p
      join public.rr_material_categories mc on mc.id=p.material_category_id
      where p.cb_id=b.id and lower(coalesce(p.entry_notes,''))<>'regular cloth'
    ),'[]'::jsonb),
    'art_status',case when b.art_due then 'DUE' else 'COMPLETE' end,
    'art_combo_status',case when exists(
      select 1 from public.rr_cb_units u
      where u.purchase_id=b.id and coalesce(u.combo_mode,'single')<>'single'
    ) then 'MULTI / COMBO' else 'SINGLE' end,
    'art_actions',coalesce((
      select jsonb_agg(jsonb_build_object(
        'cb_unit_id',u.id,
        'cb_code',u.cb_code,
        'href','real-art-decide-master.html?cb_unit_id='||u.id||'&from=CB_DEPARTMENT'
      ) order by u.division_index)
      from public.rr_cb_units u
      left join public.rr_pm_decision_status_v802 d on d.cb_unit_id=u.id
      where u.purchase_id=b.id and coalesce(u.is_final,true)
        and not coalesce(d.all_decisions_complete,false)
    ),'[]'::jsonb),
    'message',case
      when b.resolved_state='OPEN' then 'CB created · Final review pending'
      when b.resolved_state='CLOSE' then 'SENT TO CUTTING'
      when b.art_due then 'Art / Art Combo decision active'
      when b.due_count>0 then 'ART COMPLETE · MATERIAL DUE '||b.due_count||' · CUTTING HOLD'
      else 'CUTTING READY'
    end,
    'event_at',b.updated_at,
    'edit_href','real-cb-new-v9130-fix2.html?cb_id='||b.id||'&from=CB_DEPARTMENT',
    'read_only',b.resolved_state='CLOSE'
  ) order by b.updated_at desc),'[]'::jsonb) into cards
  from projected b
  left join lateral(
    select p.* from public.rr_cb_purchase_entries p
    where p.cb_id=b.id and lower(coalesce(p.entry_notes,''))='regular cloth'
    order by p.created_at limit 1
  ) r on true
  where (p_state is null or upper(p_state)=b.resolved_state)
    and (
      nullif(trim(coalesce(p_search,'')),'') is null
      or b.cb_no ilike '%'||trim(p_search)||'%'
      or coalesce(r.fabric_name,'') ilike '%'||trim(p_search)||'%'
    );

  return jsonb_build_object(
    'cards',cards,
    'department_code','PURCHASE',
    'department_name','CB Department'
  );
end
$function$;

revoke all on function public.rr_cb_department_cards_v600(text,text) from public,anon;
grant execute on function public.rr_cb_department_cards_v600(text,text) to authenticated;

comment on function public.rr_cb_department_cards_v600(text,text) is
  'TEST71 V611 CB Department projection: canonical child decision status drives every Art action; DUE blocks Cutting, not Art.';

comment on function public.rr_pm_save_decision_bundle_v804(uuid,uuid,text,uuid[],text,uuid[],text,uuid[],text) is
  'Canonical Product Master Art/Print/Sticker/Metal decision engine; V611 serializes same-child retry before mutation.';

create or replace function public.rr_test_cb_working_art_v611()
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_regular uuid;
  v_additional uuid;
  v_art uuid;
  v_cb_no text:='TEST71-V611-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  v_payload jsonb;
  v_draft jsonb;
  v_confirm jsonb;
  v_partial jsonb;
  v_retry jsonb;
  v_complete jsonb;
  v_partial_card jsonb;
  v_complete_card jsonb;
  v_cb uuid;
  v_unit uuid;
  v_result jsonb;
  v_residue integer;
begin
  perform public.rr_cb_department_assert_authority_v600();
  select id into v_regular from public.rr_material_categories
  where lower(category_code)='regular-cloth' and is_active limit 1;
  select id into v_additional from public.rr_material_categories
  where is_active and id<>v_regular and not lower(coalesce(category_code,'')) like '%matching%'
  order by sort_order,category_name limit 1;
  select id into v_art from public.rr_art_master where is_active order by created_at,id limit 1;
  if v_regular is null or v_additional is null or v_art is null then
    raise exception 'V611 proof requires Regular Cloth, one additional Material and one active Art.';
  end if;

  begin
    v_payload:=jsonb_build_object(
      'cb_no',v_cb_no,'division_count',1,'colour_count',1,
      'remarks','TEST71 V611 rollback-only WORKING Art proof',
      'colours',jsonb_build_array(jsonb_build_object(
        'index',1,'name','Colour 1',
        'image_url','https://example.invalid/test71-v611.jpg','confirmed',true
      )),
      'regular',jsonb_build_object(
        'client_key',gen_random_uuid(),'category_id',v_regular,
        'vendor','TEST71 Supplier','bill_no','TEST71-V611','bill_date',current_date,
        'fabric_name','TEST71 Regular Cloth','qty',120,'rate',365,'amount',43800,
        'rolls',jsonb_build_array(jsonb_build_object('colour_index',1,'roll_no',1,'qty',120))
      ),
      'materials',jsonb_build_array(jsonb_build_object(
        'client_key',gen_random_uuid(),'category_id',v_additional,
        'state','DUE','unit','PCS','cutting_blocking',true,
        'vendor','','bill_no','','bill_date','','fabric_name','','qty','','rate',null,'amount',null
      ))
    );
    v_draft:=public.rr_cb_department_save_v600(null,gen_random_uuid(),false,v_payload);
    v_cb:=(v_draft->>'cb_id')::uuid;
    v_confirm:=public.rr_cb_department_save_v600(v_cb,gen_random_uuid(),true,v_payload);
    select id into v_unit from public.rr_cb_units
    where purchase_id=v_cb and coalesce(is_final,true)
    order by division_index,id limit 1;

    v_partial:=public.rr_pm_save_decision_bundle_v804(
      v_unit,v_art,'DUE','{}'::uuid[],'NA','{}'::uuid[],'NA','{}'::uuid[],'TEST'
    );
    v_retry:=public.rr_pm_save_decision_bundle_v804(
      v_unit,v_art,'DUE','{}'::uuid[],'NA','{}'::uuid[],'NA','{}'::uuid[],'TEST'
    );
    select value into v_partial_card
    from jsonb_array_elements(public.rr_cb_department_cards_v600('WORKING',v_cb_no)->'cards')
    where value->>'cb_id'=v_cb::text;

    v_complete:=public.rr_pm_save_decision_bundle_v804(
      v_unit,v_art,'NA','{}'::uuid[],'NA','{}'::uuid[],'NA','{}'::uuid[],'TEST'
    );
    select value into v_complete_card
    from jsonb_array_elements(public.rr_cb_department_cards_v600('WORKING',v_cb_no)->'cards')
    where value->>'cb_id'=v_cb::text;

    v_result:=jsonb_build_object(
      'confirm',v_confirm,
      'partial',v_partial,
      'retry',v_retry,
      'complete',v_complete,
      'partial_art_status',v_partial_card->>'art_status',
      'partial_action_count',jsonb_array_length(coalesce(v_partial_card->'art_actions','[]'::jsonb)),
      'complete_art_status',v_complete_card->>'art_status',
      'complete_action_count',jsonb_array_length(coalesce(v_complete_card->'art_actions','[]'::jsonb)),
      'complete_message',v_complete_card->>'message',
      'assignment_rows',(select count(*) from public.rr_cb_art_assignments where cb_id=v_unit),
      'due_rows',(select count(*) from public.rr_cb_purchase_entries where cb_id=v_cb and requirement_state='DUE')
    );
    raise exception using errcode='P6111',message='TEST71_CB_WORKING_ART_ROLLBACK';
  exception when sqlstate 'P6111' then
    if sqlerrm<>'TEST71_CB_WORKING_ART_ROLLBACK' then raise; end if;
  end;

  select count(*) into v_residue from public.rr_fabric_purchases where cb_no=v_cb_no;
  return v_result||jsonb_build_object(
    'exact_invariant',v_result->'confirm'->>'state'='WORKING'
      and (v_result->>'partial_art_status')='DUE'
      and (v_result->>'partial_action_count')::integer=1
      and (v_result->>'complete_art_status')='COMPLETE'
      and (v_result->>'complete_action_count')::integer=0
      and (v_result->>'complete_message')='ART COMPLETE · MATERIAL DUE 1 · CUTTING HOLD'
      and (v_result->>'assignment_rows')::integer=1
      and (v_result->>'due_rows')::integer=1,
    'rolled_back',v_residue=0,
    'fixture_residue',v_residue
  );
end
$function$;

revoke all on function public.rr_test_cb_working_art_v611() from public,anon;
grant execute on function public.rr_test_cb_working_art_v611() to authenticated,service_role;

comment on function public.rr_test_cb_working_art_v611() is
  'Rollback-only TEST71 proof: DUE allows WORKING/Art, partial decisions retain the action, identical retry stays single, completion removes the action, residue zero.';

notify pgrst,'reload schema';
commit;
