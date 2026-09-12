-- Hide completed pre-sale conversations only after canonical despatch is received/finalized.
alter table public.rr_real_chat_message_bridge_v70 add column if not exists archived_at timestamptz;
alter table public.rr_real_chat_message_bridge_v70 add column if not exists archive_reason text;
create index if not exists rr_rc_bridge_active_v71 on public.rr_real_chat_message_bridge_v70(archived_at,department_code,sent_at desc);

create or replace function public.rr_real_chat_reconcile_sales_dispatch_archive_v71()
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare n integer:=0; x integer;
begin
  -- Direct lot-scoped production messages. Sales/return/RCI/accounting remain in their own lifecycle.
  update public.rr_real_chat_message_bridge_v70 b set archived_at=coalesce(b.archived_at,now()),archive_reason='SALES_DESPATCH_RECEIVED'
  where b.archived_at is null and b.source_module in ('UPM','UPM_RATE','PACKING','PACKING_RATE','MEDIA_AI','CUTTING','DESPATCH')
    and nullif(b.personal_payload->>'lot_no','') is not null
    and exists(select 1 from public.rr_fg_despatch_custody_v9361 c join public.rr_fg_despatch_v787 d on d.id=c.despatch_id
      where d.data_mode='TEST' and upper(c.lot_no)=upper(b.personal_payload->>'lot_no') and upper(d.status)='RECEIVED');
  get diagnostics x=row_count;n:=n+x;

  -- A shared Product Master decision archives only after every released lot for that D/unit is sellable.
  update public.rr_real_chat_message_bridge_v70 b set archived_at=coalesce(b.archived_at,now()),archive_reason='ALL_UNIT_LOTS_DESPATCHED'
  where b.archived_at is null and b.source_module='PRODUCT_MASTER'
    and exists(select 1 from public.rr_cb_art_assignments a join public.rr_cutting_lots_v3 l on l.cb_unit_id=a.cb_id where a.id::text=b.source_record_id)
    and not exists(select 1 from public.rr_cb_art_assignments a join public.rr_cutting_lots_v3 l on l.cb_unit_id=a.cb_id
      where a.id::text=b.source_record_id and not exists(select 1 from public.rr_fg_despatch_custody_v9361 c
        join public.rr_fg_despatch_v787 d on d.id=c.despatch_id where d.data_mode='TEST'
          and upper(c.lot_no)=upper(l.lot_no) and upper(d.status)='RECEIVED'));
  get diagnostics x=row_count;n:=n+x;

  -- Shared CB/Matching purchase messages archive only when all released lots under that CB are sellable.
  update public.rr_real_chat_message_bridge_v70 b set archived_at=coalesce(b.archived_at,now()),archive_reason='ALL_CB_LOTS_DESPATCHED'
  where b.archived_at is null and b.source_module in ('CB_PURCHASE','MATCHING_PURCHASE')
    and exists(select 1 from public.rr_cutting_lots_v3 l join public.rr_cb_purchase_entries p on p.cb_id=l.cb_purchase_id where p.id::text=b.source_record_id)
    and not exists(select 1 from public.rr_cutting_lots_v3 l join public.rr_cb_purchase_entries p on p.cb_id=l.cb_purchase_id
      where p.id::text=b.source_record_id and not exists(select 1 from public.rr_fg_despatch_custody_v9361 c
        join public.rr_fg_despatch_v787 d on d.id=c.despatch_id where d.data_mode='TEST'
          and upper(c.lot_no)=upper(l.lot_no) and upper(d.status)='RECEIVED'));
  get diagnostics x=row_count;n:=n+x;
  return n;
end $$;
revoke all on function public.rr_real_chat_reconcile_sales_dispatch_archive_v71() from public,anon,authenticated;

create or replace function public.rr_real_chat_sellable_archive_trigger_v71() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin perform public.rr_real_chat_reconcile_sales_dispatch_archive_v71();return null;
exception when others then raise warning 'TEST70 sales dispatch archive reconciliation deferred: %',sqlerrm;return null;end $$;
drop trigger if exists rr_real_chat_sellable_archive_despatch_v71 on public.rr_fg_despatch_v787;
create trigger rr_real_chat_sellable_archive_despatch_v71 after insert or update on public.rr_fg_despatch_v787
for each statement execute function public.rr_real_chat_sellable_archive_trigger_v71();
drop trigger if exists rr_real_chat_sellable_archive_acceptance_v71 on public.rr_fg_despatch_acceptance_v9356;
create trigger rr_real_chat_sellable_archive_acceptance_v71 after insert or update on public.rr_fg_despatch_acceptance_v9356
for each statement execute function public.rr_real_chat_sellable_archive_trigger_v71();

select public.rr_real_chat_reconcile_sales_dispatch_archive_v71();
