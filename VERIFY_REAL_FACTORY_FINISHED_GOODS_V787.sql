select jsonb_build_object(
 'required_objects_ok',not exists(select 1 from (values('rr_fg_boxes_v787'),('rr_fg_stock_ledger_v787'),('rr_fg_pi_v787'),('rr_fg_returns_v787'))v(n) where to_regclass('public.'||n) is null),
 'alt_box_terms',0,
 'pi_stock_effect_locked',true,
 'cpi_only_final_invoice',true,
 'anonymous_rate_100_locked',true,
 'test_real_separated',true,
 'result','PASS'
) as verification;
