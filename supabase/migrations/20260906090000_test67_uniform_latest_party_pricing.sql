-- TEST67 legacy normalization: every existing snapshot uses its party's latest
-- universal pricing pair.  Future writes remain protected by uniform triggers.
drop trigger if exists rr_partner_uniform_collection_pricing_v67 on public.rr_market_partner_collection_line_v67;
drop trigger if exists rr_partner_uniform_requirement_pricing_v67 on public.rr_market_partner_order_line_v67;

update public.rr_market_partner_collection_line_v67 l
set margin_amount=c.default_margin_amount,
    distributor_sale_rate=l.base_rate+c.default_margin_amount,
    discount_amount=c.default_discount_amount,
    final_customer_rate=greatest(0,l.base_rate+c.default_margin_amount-c.default_discount_amount)
from public.rr_market_partner_collection_v67 pc
join public.rr_market_partner_customer_v67 c on c.id=pc.partner_customer_id
where l.collection_id=pc.id and c.data_mode='TEST';

update public.rr_market_partner_order_line_v67 l
set rate_enhancement=c.default_margin_amount,
    customer_discount=c.default_discount_amount,
    final_customer_rate=greatest(0,l.base_rate+c.default_margin_amount-c.default_discount_amount)
from public.rr_market_partner_order_v67 o
join public.rr_market_partner_customer_v67 c on c.id=o.partner_customer_id
where l.order_id=o.id and c.data_mode='TEST';

create trigger rr_partner_uniform_collection_pricing_v67 before insert or update of margin_amount,discount_amount
on public.rr_market_partner_collection_line_v67 for each row execute function public.rr_market_partner_uniform_collection_pricing_v67();
create trigger rr_partner_uniform_requirement_pricing_v67 before insert or update of rate_enhancement,customer_discount
on public.rr_market_partner_order_line_v67 for each row execute function public.rr_market_partner_uniform_requirement_pricing_v67();
