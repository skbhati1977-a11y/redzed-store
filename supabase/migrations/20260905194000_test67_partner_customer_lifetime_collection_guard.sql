-- TEST67 distributor -> customer parity guard.
-- A sample sent once to a distributor customer must never reappear in that
-- customer's later Collection picker, even after a Requirement/PI closes the
-- previous Collection root.

create or replace function public.rr_market_partner_collection_line_once_v79()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_owner uuid;
  v_partner_customer uuid;
begin
  select pc.owner_customer_id,pc.partner_customer_id
  into v_owner,v_partner_customer
  from public.rr_market_partner_collection_v67 pc
  where pc.id=new.collection_id;

  if v_owner is null or v_partner_customer is null then
    raise exception 'TEST67 Collection parent is unavailable.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      v_owner::text||'|'||v_partner_customer::text||'|'||lower(btrim(new.lot_no)),
      79
    )
  );

  if tg_op='UPDATE' then
    if exists(
      select 1
      from public.rr_market_partner_collection_line_v67 prior
      join public.rr_market_partner_collection_v67 pc
        on pc.id=prior.collection_id
      where pc.owner_customer_id=v_owner
        and pc.partner_customer_id=v_partner_customer
        and pc.status<>'CANCELLED'
        and lower(btrim(prior.lot_no))=lower(btrim(new.lot_no))
        and (prior.collection_id,prior.lot_no)<>
          (old.collection_id,old.lot_no)
    ) then
      raise exception
        'Lot % was already sent to this customer. Select only fresh samples.',
        new.lot_no;
    end if;
  elsif exists(
    select 1
    from public.rr_market_partner_collection_line_v67 prior
    join public.rr_market_partner_collection_v67 pc
      on pc.id=prior.collection_id
    where pc.owner_customer_id=v_owner
      and pc.partner_customer_id=v_partner_customer
      and pc.status<>'CANCELLED'
      and lower(btrim(prior.lot_no))=lower(btrim(new.lot_no))
  ) then
    raise exception
      'Lot % was already sent to this customer. Select only fresh samples.',
      new.lot_no;
  end if;

  return new;
end
$$;

drop trigger if exists rr_market_partner_collection_line_once_v78
  on public.rr_market_partner_collection_line_v67;
drop trigger if exists rr_market_partner_collection_line_once_v79
  on public.rr_market_partner_collection_line_v67;
create trigger rr_market_partner_collection_line_once_v79
before insert or update of collection_id,lot_no
on public.rr_market_partner_collection_line_v67
for each row execute function public.rr_market_partner_collection_line_once_v79();

revoke all on function public.rr_market_partner_collection_line_once_v79()
  from public,anon,authenticated;

drop function if exists public.rr_market_partner_collection_line_once_v78();

comment on function public.rr_market_partner_collection_line_once_v79() is
  'TEST67 invariant: one lot can be sent only once to one distributor customer.';
