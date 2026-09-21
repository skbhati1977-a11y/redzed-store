-- Keep the aggregate CB Department card, but route Art decisions through the
-- existing division/child engine's cb_unit_id contract.
create or replace function public.rr_cb_department_cards_v600(p_state text default null,p_search text default null)
returns jsonb language plpgsql stable security definer set search_path='public' as $function$
declare cards jsonb; ident jsonb:=public.rr_upm_effective_identity_v200(); worker uuid:=public.rr_upm_current_worker_id_v9112(); role_code text;
begin
  perform public.rr_assert_active_user_v1();
  role_code:=upper(coalesce(ident->>'role_code',ident->>'resolved_role',''));
  if role_code not in('OWNER','SUPER_ADMIN','ADMIN') and not exists(
    select 1 from public.rr_real_chat_department_membership_v70 m
    where m.worker_id=worker and m.is_active
      and public.rr_real_chat_canonical_department_v83(m.department_code)='PURCHASE'
  ) then raise exception 'CB Department membership required.' using errcode='42501'; end if;
  with base as(
    select fp.*,
      case when fp.cb_department_state='OPEN' then 'OPEN'
        when exists(select 1 from public.rr_cb_units u where u.purchase_id=fp.id and coalesce(u.is_final,true))
         and not exists(select 1 from public.rr_cb_units u where u.purchase_id=fp.id and coalesce(u.is_final,true)
          and not exists(select 1 from public.rr_cutting_lots_v3 s where s.cb_unit_id=u.id and upper(coalesce(s.status,'')) not in('CANCELLED','CANCELED')
            union all select 1 from public.rr_production_lots m where m.cb_unit_id=u.id and upper(coalesce(m.status,'')) not in('CANCELLED','CANCELED'))) then 'CLOSE'
        else 'WORKING' end resolved_state
    from public.rr_fabric_purchases fp where upper(coalesce(fp.operation_status,'ACTIVE'))='ACTIVE'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'event_key','CB_DEPARTMENT:'||b.id,'source_module','CB_DEPARTMENT','card_type','CB_DEPARTMENT',
    'cb_id',b.id,'cb_no',b.cb_no,'lot_no',b.cb_no,'department_code','PURCHASE','department_name','CB Department',
    'source_status',b.resolved_state,'canonical_state',b.resolved_state,'division_count',b.division_count,
    'colour_count',b.colour_count,'quantity',coalesce(r.quantity,b.total_weight),'quantity_unit','KG',
    'supplier',r.vendor_name,'fabric_name',r.fabric_name,'bill_no',r.vendor_bill_no,'bill_date',r.bill_date,
    'roll_count',coalesce((select count(*) from public.rr_cb_purchase_rolls z where z.purchase_entry_id=r.id),0),
    'amount',r.amount,'actual_rate',r.rate,'pending_material_count',(select count(*) from public.rr_cb_purchase_entries p where p.cb_id=b.id and p.requirement_state='DUE'),
    'materials',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',mc.category_name,'state',p.requirement_state,'qty',p.quantity,'unit',p.unit,'cutting_blocking',p.cutting_blocking) order by mc.sort_order,mc.category_name) from public.rr_cb_purchase_entries p join public.rr_material_categories mc on mc.id=p.material_category_id where p.cb_id=b.id and lower(coalesce(p.entry_notes,''))<>'regular cloth'),'[]'::jsonb),
    'art_status',case when exists(select 1 from public.rr_cb_units u where u.purchase_id=b.id and coalesce(u.is_final,true) and not exists(select 1 from public.rr_cb_art_assignments a where a.cb_id=u.id)) then 'DUE' else 'COMPLETE' end,
    'art_combo_status',case when exists(select 1 from public.rr_cb_units u where u.purchase_id=b.id and coalesce(u.combo_mode,'single')<>'single') then 'MULTI / COMBO' else 'SINGLE' end,
    'art_actions',coalesce((select jsonb_agg(jsonb_build_object('cb_unit_id',u.id,'cb_code',u.cb_code,'href','real-art-decide-master.html?cb_unit_id='||u.id||'&from=CB_DEPARTMENT') order by u.division_index)
      from public.rr_cb_units u where u.purchase_id=b.id and coalesce(u.is_final,true)
        and not exists(select 1 from public.rr_cb_art_assignments a where a.cb_id=u.id)),'[]'::jsonb),
    'message',case b.resolved_state when 'OPEN' then 'CB created · Final review pending' when 'WORKING' then 'Art / Art Combo decision active' else 'SENT TO CUTTING' end,
    'event_at',b.updated_at,'edit_href','real-cb-new-v9130-fix2.html?cb_id='||b.id||'&from=CB_DEPARTMENT',
    'read_only',b.resolved_state='CLOSE'
  ) order by b.updated_at desc),'[]'::jsonb) into cards
  from base b left join lateral(
    select p.* from public.rr_cb_purchase_entries p where p.cb_id=b.id and lower(coalesce(p.entry_notes,''))='regular cloth' order by p.created_at limit 1
  )r on true
  where (p_state is null or upper(p_state)=b.resolved_state)
    and (nullif(trim(coalesce(p_search,'')),'') is null or b.cb_no ilike '%'||trim(p_search)||'%'
      or coalesce(r.fabric_name,'') ilike '%'||trim(p_search)||'%');
  return jsonb_build_object('cards',cards,'department_code','PURCHASE','department_name','CB Department');
end $function$;
revoke all on function public.rr_cb_department_cards_v600(text,text) from public,anon;
grant execute on function public.rr_cb_department_cards_v600(text,text) to authenticated;

comment on function public.rr_cb_department_cards_v600(text,text) is
  'Direct App/Backend/Real Chat CB Department projection with canonical child Art actions; V601.';
