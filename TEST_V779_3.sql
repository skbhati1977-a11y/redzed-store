
-- ============================================================
-- V779.3 SAFE TEST QUERIES
-- Use a real TEST payroll_id where instructed.
-- ============================================================

-- 1. Management board
-- select public.rr_get_payroll_management_board_v779_3(
--   '2026-07-01'::date,
--   'TEST'
-- );

-- 2. Payroll summary
-- select public.rr_get_payroll_summary_v779_3(
--   '<PAYROLL_ID>'::uuid
-- );

-- 3. Net Extra Work drawer
-- select public.rr_get_payroll_section_details_v779_3(
--   '<PAYROLL_ID>'::uuid,
--   'NET_EXTRA_WORK'
-- );

-- 4. PDF-ready payload, FINAL/PAID payroll only
-- select public.rr_get_payslip_payload_v779_3(
--   '<PAYROLL_ID>'::uuid
-- );

-- 5. WhatsApp-ready payload, FINAL/PAID payroll only
-- select public.rr_get_whatsapp_payslip_payload_v779_3(
--   '<PAYROLL_ID>'::uuid
-- );
