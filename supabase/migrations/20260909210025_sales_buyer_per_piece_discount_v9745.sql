begin;
alter table public.rr_buyers_v787 drop constraint if exists rr_buyers_v787_discount_type_check;
alter table public.rr_buyers_v787 add constraint rr_buyers_v787_discount_type_check
  check(discount_type in('FLAT','PERCENT','PER_PIECE'));
commit;
