-- TEST67: collection lines use (collection_id, lot_no) as their primary key.
-- Keep the uniform pricing rule without referencing the removed/nonexistent id.

create or replace function public.rr_market_partner_uniform_collection_pricing_v67()
returns trigger
language plpgsql
set search_path=''
as $function$
begin
  if tg_op='UPDATE' then
    if exists(
      select 1
      from public.rr_market_partner_collection_line_v67 x
      where x.collection_id=new.collection_id
        and (x.collection_id,x.lot_no)<>(old.collection_id,old.lot_no)
        and (
          x.margin_amount is distinct from new.margin_amount
          or x.discount_amount is distinct from new.discount_amount
        )
    ) then
      raise exception 'One collection/update must use one margin and one discount for every lot.';
    end if;
  elsif exists(
    select 1
    from public.rr_market_partner_collection_line_v67 x
    where x.collection_id=new.collection_id
      and (
        x.margin_amount is distinct from new.margin_amount
        or x.discount_amount is distinct from new.discount_amount
      )
  ) then
    raise exception 'One collection/update must use one margin and one discount for every lot.';
  end if;

  return new;
end
$function$;

