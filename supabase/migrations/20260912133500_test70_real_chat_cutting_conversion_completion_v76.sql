-- TEST70 only: a CB-to-Lot conversion is a completed action message. It must
-- remain visible in CLOSE history without changing the canonical OPEN queue.
begin;

create or replace function public.rr_real_chat_truthful_cutting_lot_v75()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_lot text; v_operator text; v_performer text; v_cb_no text; v_qty numeric;
begin
  if new.source_module<>'CUTTING' or new.canonical_key not like 'LOT_RELEASE:%' then return new; end if;
  v_lot:=new.personal_payload->>'lot_no';
  select nullif(trim(l.operator_name),''),
         (select p.full_name from public.rr_user_profiles p where p.auth_user_id=l.created_by
          and coalesce(p.is_active,false) order by p.updated_at desc nulls last limit 1),
         coalesce(m.cb_no,u.cb_base_no),
         (select sum(coalesce(b.actual_qty,b.planned_qty,0)) from public.rr_cutting_breakup_v3 b where b.cutting_lot_id=l.id)
  into v_operator,v_performer,v_cb_no,v_qty
  from public.rr_cutting_lots_v3 l
  left join public.rr_cb_master m on m.id=l.cb_purchase_id
  left join public.rr_cb_units u on u.id=l.cb_unit_id
  where l.lot_no=v_lot order by l.created_at desc limit 1;

  if v_operator is null then return new; end if;
  new.personal_payload:=new.personal_payload||jsonb_strip_nulls(jsonb_build_object(
    'sender_name',v_operator,'performed_by_name',v_performer,
    'on_behalf_of_name',case when v_performer is not null and lower(v_performer)<>lower(v_operator) then v_operator end,
    'cb_no',v_cb_no,'qty',v_qty,'message','CB से Lot बनाया','message_status','COMPLETED'));
  new.group_payload:=new.group_payload||jsonb_strip_nulls(jsonb_build_object(
    'sender_name',v_operator,'performed_by_name',v_performer,
    'on_behalf_of_name',case when v_performer is not null and lower(v_performer)<>lower(v_operator) then v_operator end,
    'cb_no',v_cb_no,'qty',v_qty,'message','CB से Lot बनाया','message_status','COMPLETED'));
  return new;
end $$;

-- Re-project legacy and present conversion messages through V73/V75/V74.
update public.rr_real_chat_message_bridge_v70
set source_event_type=source_event_type
where source_module='CUTTING' and canonical_key like 'LOT_RELEASE:%';

comment on function public.rr_real_chat_truthful_cutting_lot_v75() is
'TEST70 legacy/present/future CB-to-Lot messages show the real operator and remain completed history, independently of canonical OPEN eligibility.';
commit;
