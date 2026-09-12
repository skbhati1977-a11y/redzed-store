-- PI/CI commercial rates are snapshots. They must never replace the canonical
-- Packing/Admin approved rate or affect RRQ while the document is still a PI.

begin;

drop trigger if exists rrq_pi_cpi_rate_change_v9300
  on public.rr_fg_pi_lines_v787;

create or replace function public.rrq_apply_pi_cpi_rate_change_v9300()
returns trigger
language plpgsql
security definer
set search_path='public'
as $function$
begin
  return new;
end
$function$;

do $repair$
declare
  v_balance numeric;
  r record;
begin
  if exists(
    select 1 from public.rrq_rate_ledger_v9300
    where event_type='PI_RATE_COMPOUNDING_REPAIR_V9738'
  ) then
    return;
  end if;

  for r in
    with affected as (
      select l.data_mode,l.lot_no,sum(l.quota_delta) bad_delta
      from public.rrq_rate_ledger_v9300 l
      where l.event_type='PI_CPI_RATE_CHANGE'
      group by l.data_mode,l.lot_no
    ), restored as (
      select a.*,
        (select x.new_rate
         from public.rrq_rate_ledger_v9300 x
         where x.data_mode=a.data_mode
           and upper(trim(x.lot_no))=upper(trim(a.lot_no))
           and x.event_type='PACKING_ADMIN'
         order by x.created_at desc
         limit 1) approved_rate
      from affected a
    )
    select * from restored where approved_rate is not null
  loop
    update public.rrq_lot_rates_v9300 q
       set final_sale_rate=r.approved_rate,
           rrq_adjustment_per_pc=r.approved_rate-q.base_sale_rate,
           updated_at=now()
     where q.data_mode=r.data_mode
       and upper(trim(q.lot_no))=upper(trim(r.lot_no));

    update public.rr_fg_products_v787 p
       set sale_rate=r.approved_rate
     where upper(trim(p.lot_no))=upper(trim(r.lot_no));

    update public.rrq_balance_v9300 b
       set balance=b.balance-r.bad_delta,updated_at=now()
     where b.data_mode=r.data_mode
     returning b.balance into v_balance;

    insert into public.rrq_rate_ledger_v9300(
      data_mode,lot_no,event_type,ref_type,qty,previous_rate,new_rate,
      delta_per_pc,quota_delta,balance_after,reason
    ) values (
      r.data_mode,r.lot_no,'PI_RATE_COMPOUNDING_REPAIR_V9738','SYSTEM_REPAIR',0,
      r.approved_rate,r.approved_rate,0,-r.bad_delta,v_balance,
      'Restore latest Packing/Admin approved rate; reverse draft PI trigger balance impact'
    );
  end loop;
end
$repair$;

revoke all on function public.rrq_apply_pi_cpi_rate_change_v9300()
  from public,anon,authenticated;
grant execute on function public.rrq_apply_pi_cpi_rate_change_v9300()
  to service_role;

commit;
