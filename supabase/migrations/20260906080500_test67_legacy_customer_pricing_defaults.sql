-- TEST67 legacy distributor-customer pricing baseline.
alter table public.rr_market_partner_customer_v67
  alter column default_margin_amount set default 10,
  alter column default_discount_amount set default 5;

-- Existing TEST67 legacy customers receive the agreed universal starting values.
-- Future owner edits remain customer-specific and are not overwritten again.
update public.rr_market_partner_customer_v67
set default_margin_amount=10,
    default_discount_amount=5,
    updated_at=now()
where data_mode='TEST';
