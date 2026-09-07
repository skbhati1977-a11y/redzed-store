-- TEST67: duplicate protection is scoped to one open requirement cycle.
-- Once that requirement closes, the next collection number may reuse any lot.

create or replace function public.rr_market_partner_collection_line_once_v79()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_owner uuid;
  v_partner_customer uuid;
  v_root uuid;
begin
  select pc.owner_customer_id,
         pc.partner_customer_id,
         coalesce(pc.root_collection_id,pc.id)
    into v_owner,v_partner_customer,v_root
  from public.rr_market_partner_collection_v67 pc
  where pc.id=new.collection_id;

  if v_owner is null or v_partner_customer is null or v_root is null then
    raise exception 'TEST67 Collection parent is unavailable.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      v_owner::text||'|'||v_partner_customer::text||'|'||v_root::text||'|'||lower(btrim(new.lot_no)),
      79
    )
  );

  if exists(
    select 1
    from public.rr_market_partner_collection_line_v67 prior
    join public.rr_market_partner_collection_v67 pc
      on pc.id=prior.collection_id
    where pc.owner_customer_id=v_owner
      and pc.partner_customer_id=v_partner_customer
      and coalesce(pc.root_collection_id,pc.id)=v_root
      and pc.status<>'CANCELLED'
      and lower(btrim(prior.lot_no))=lower(btrim(new.lot_no))
      and (
        tg_op<>'UPDATE'
        or (prior.collection_id,prior.lot_no)<>(old.collection_id,old.lot_no)
      )
  ) then
    raise exception
      'Lot % was already sent in the current open requirement. Select it after closing this requirement, or select another sample.',
      new.lot_no;
  end if;

  return new;
end
$function$;

revoke all on function public.rr_market_partner_collection_line_once_v79()
  from public,anon,authenticated;

comment on function public.rr_market_partner_collection_line_once_v79() is
  'TEST67 invariant: a lot is unique only inside one open collection/requirement root; a new numbered cycle starts fresh.';
