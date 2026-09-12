-- TEST70 V103: source-truth Purchase lifecycle and compact CLOSE metadata.
-- Existing CB, Art and Cutting engines remain authoritative.
begin;

create or replace function public.rr_real_chat_reconcile_cb_close_v103()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_rows integer:=0;
begin
 with lot_rollup as (
  select l.cb_purchase_id,
   string_agg(l.lot_no, ', ' order by l.created_at,l.lot_no) lot_numbers,
   sum(coalesce(nullif(r.verified_cut_qty,0),nullif(r.original_cut_qty,0),
                nullif(r.total_qty,0),nullif(l.actual_pcs,0),nullif(l.planned_pcs,0),0)) cutting_pieces,
   jsonb_agg(jsonb_build_object(
    'lot_no',l.lot_no,
    'cutting_pieces',coalesce(nullif(r.verified_cut_qty,0),nullif(r.original_cut_qty,0),
                              nullif(r.total_qty,0),nullif(l.actual_pcs,0),nullif(l.planned_pcs,0),0)
   ) order by l.created_at,l.lot_no) lots
  from public.rr_cutting_lots_v3 l
  left join lateral (
   select u.verified_cut_qty,u.original_cut_qty,u.total_qty
   from public.rr_upm_lot_registry u
   where u.source_id=l.id::text or u.lot_no=l.lot_no
   order by (u.source_id=l.id::text) desc,u.updated_at desc limit 1
  ) r on true
  group by l.cb_purchase_id
 ), resolved as (
  select b.id,b.source_record_id,lr.lot_numbers,lr.cutting_pieces,lr.lots,
   case
    when lr.cb_purchase_id is not null then 'CLOSE'
    when exists(select 1 from public.rr_cb_units u where u.purchase_id=b.source_record_id::uuid)
     and not exists(
      select 1 from public.rr_cb_units u
      left join public.rr_pm_decision_status_v802 d on d.cb_unit_id=u.id
      where u.purchase_id=b.source_record_id::uuid and coalesce(d.all_decisions_complete,false)=false
     ) then 'WORKING'
    else 'OPEN'
   end canonical_state
  from public.rr_real_chat_message_bridge_v70 b
  left join lot_rollup lr on lr.cb_purchase_id=b.source_record_id::uuid
  where b.archived_at is null and b.source_module='CB_PURCHASE'
   and b.source_event_type='CREATE_CB_SUCCEEDED'
   and b.source_record_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
 )
 update public.rr_real_chat_message_bridge_v70 b
 set personal_payload=(coalesce(b.personal_payload,'{}'::jsonb)-'lot_numbers'-'cutting_pieces'-'cutting_lots')
      ||jsonb_strip_nulls(jsonb_build_object('canonical_state',r.canonical_state,
       'lot_numbers',r.lot_numbers,'cutting_pieces',r.cutting_pieces,'cutting_lots',r.lots)),
     group_payload=(coalesce(b.group_payload,'{}'::jsonb)-'lot_numbers'-'cutting_pieces'-'cutting_lots')
      ||jsonb_strip_nulls(jsonb_build_object('canonical_state',r.canonical_state,
       'lot_numbers',r.lot_numbers,'cutting_pieces',r.cutting_pieces,'cutting_lots',r.lots)),
     action_code=case when r.canonical_state='OPEN' then 'ART_DECIDE_SUBMIT' else null end,
     action_label=case when r.canonical_state='OPEN' then 'DECIDE ART / PRINT / STICKER / METAL ID' else null end
 from resolved r where b.id=r.id;
 get diagnostics v_rows=row_count;
 return jsonb_build_object('purchase_rows',v_rows,
  'close_with_lot',(select count(*) from public.rr_real_chat_message_bridge_v70
   where archived_at is null and source_module='CB_PURCHASE'
    and personal_payload->>'canonical_state'='CLOSE' and personal_payload ? 'lot_numbers'),
  'close_without_lot',(select count(*) from public.rr_real_chat_message_bridge_v70
   where archived_at is null and source_module='CB_PURCHASE'
    and personal_payload->>'canonical_state'='CLOSE' and not (personal_payload ? 'lot_numbers')));
end $$;

revoke all on function public.rr_real_chat_reconcile_cb_close_v103() from public,anon;
grant execute on function public.rr_real_chat_reconcile_cb_close_v103() to authenticated,service_role;

create or replace function public.rr_real_chat_cb_close_trigger_v103()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 perform public.rr_real_chat_reconcile_cb_close_v103(); return null;
exception when others then
 raise warning 'V103 CB close reconciliation deferred: %',sqlerrm; return null;
end $$;

do $$ declare t text; begin
 foreach t in array array['rr_cb_units','rr_cb_art_assignments','rr_cutting_lots_v3','rr_upm_lot_registry'] loop
  execute format('drop trigger if exists zzzzzzz_rr_cb_close_v103 on public.%I',t);
  execute format('create trigger zzzzzzz_rr_cb_close_v103 after insert or update or delete on public.%I for each statement execute function public.rr_real_chat_cb_close_trigger_v103()',t);
 end loop;
end $$;

select public.rr_real_chat_reconcile_cb_close_v103();
commit;
