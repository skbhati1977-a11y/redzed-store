select jsonb_build_object(
 'result',case when to_regclass('public.rr_fg_packing_assignments_v788') is not null
 and to_regprocedure('public.rr_fg_ready_packing_cards_v788(text)') is not null
 and to_regprocedure('public.rr_fg_assign_packing_v788(text,uuid,text)') is not null
 and to_regprocedure('public.rr_fg_accept_packing_v788(uuid)') is not null
 and to_regprocedure('public.rr_fg_generate_assigned_pack_v788(uuid)') is not null
 and to_regprocedure('public.rr_fg_submit_assigned_pack_v788(uuid,uuid)') is not null then 'PASS' else 'FAIL' end,
 'lot_auto_fetch',to_regprocedure('public.rr_fg_ready_packing_cards_v788(text)') is not null,
 'assign_accept_locked',to_regclass('public.rr_fg_packing_assignments_v788') is not null,
 'card_tap_algorithm',to_regprocedure('public.rr_fg_generate_assigned_pack_v788(uuid)') is not null,
 'test_real_separated',exists(select 1 from pg_constraint where conrelid='public.rr_fg_packing_assignments_v788'::regclass and pg_get_constraintdef(oid) like '%TEST%REAL%')
) verification;
