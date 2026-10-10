BEGIN;
CREATE OR REPLACE FUNCTION public.rr_worker_salary_can_view_v781() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO public AS $f$
 SELECT auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM public.rr_user_profiles p WHERE p.auth_user_id=auth.uid() AND coalesce(p.is_active,false) AND upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE')
 AND lower(coalesce(public.rr_upm_effective_identity_v200()->>'resolved_role',public.rr_upm_effective_identity_v200()->>'role_code','')) IN ('owner','super_admin','admin','manager','account','accounts','payroll','hr');
$f$;
REVOKE EXECUTE ON FUNCTION public.rr_worker_salary_can_view_v781() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_worker_salary_can_view_v781() TO authenticated;
CREATE OR REPLACE VIEW public.rr_account_grouping_v819 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT g.group_code,
    g.group_name,
    g.natural_side,
    h.header_code,
    h.header_name,
    c.category_code,
    c.category_name,
    g.display_order AS group_order,
    h.display_order AS header_order,
    c.display_order AS category_order
   FROM rr_account_categories_v805 c
     JOIN rr_account_groups_v805 g ON g.id = c.group_id
     LEFT JOIN rr_account_category_headers_v819 h ON h.category_code = c.category_code
  WHERE COALESCE(g.is_active, true) AND COALESCE(c.is_active, true) AND COALESCE(h.is_active, true)) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_acct_can_view_v805();
REVOKE ALL ON public.rr_account_grouping_v819 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_account_grouping_v819 TO authenticated;
CREATE OR REPLACE VIEW public.rr_account_reporting_base_v806 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT p.id AS posting_id,
    p.transaction_id,
    p.ledger_id,
    l.ledger_code,
    l.ledger_name,
    l.ledger_kind,
    c.category_code,
    c.category_name,
    g.group_code,
    g.group_name,
    g.natural_side AS group_natural_side,
    rm.report_type,
    rm.report_section,
    rm.normal_side AS report_normal_side,
    p.dr_amount,
    p.cr_amount,
    t.voucher_no,
    t.transaction_type,
    t.source_module,
    t.source_record_id,
    t.data_mode,
    t.status AS transaction_status,
    t.total_amount,
    p.created_at
   FROM rr_account_postings_v805 p
     JOIN rr_account_transactions_v805 t ON t.id = p.transaction_id
     JOIN rr_ledgers_v805 l ON l.id = p.ledger_id
     JOIN rr_account_categories_v805 c ON c.id = l.category_id
     JOIN rr_account_groups_v805 g ON g.id = c.group_id
     LEFT JOIN rr_account_report_map_v806 rm ON rm.category_code = c.category_code AND rm.is_active
  WHERE COALESCE(l.is_active, true)) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_acct_can_view_v805();
REVOKE ALL ON public.rr_account_reporting_base_v806 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_account_reporting_base_v806 TO authenticated;
CREATE OR REPLACE VIEW public.rr_account_source_lifecycle_v806 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT s.source_module,
    s.source_record_id,
    s.data_mode,
    s.status AS link_status,
    t.id AS account_transaction_id,
    t.voucher_no,
    t.transaction_type,
    t.total_amount,
    t.status AS transaction_status,
    t.party_ledger_id,
    t.bill_no,
    t.bill_date,
    t.transaction_datetime
   FROM rr_account_source_links_v806 s
     JOIN rr_account_transactions_v805 t ON t.id = s.account_transaction_id) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_acct_can_view_v805();
REVOKE ALL ON public.rr_account_source_lifecycle_v806 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_account_source_lifecycle_v806 TO authenticated;
CREATE OR REPLACE VIEW public.rr_accounts_due_v834 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT 'COMMITTEE'::text AS module_code,
    'ACCOUNTS'::text AS department_code,
    'ACCOUNTS_DUE'::text AS due_type,
    month_id::text AS source_id,
    scheme_code AS reference_no,
    'Committee Month '::text || month_no AS reference_detail,
    0::numeric AS due_qty,
    round(COALESCE(month_outstanding, 0::numeric), 2) AS due_amount,
    due_date::timestamp without time zone AS due_since,
        CASE
            WHEN due_date < CURRENT_DATE THEN 'OVERDUE'::text
            WHEN due_date = CURRENT_DATE THEN 'TODAY'::text
            ELSE 'UPCOMING'::text
        END AS due_state,
    due_date::timestamp without time zone AS sort_at,
    to_jsonb(q.*) AS payload
   FROM rr_committee_action_queue_v831 q
  WHERE data_mode = 'TEST'::text AND COALESCE(month_outstanding, 0::numeric) > 0::numeric) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_acct_can_view_v805();
REVOKE ALL ON public.rr_accounts_due_v834 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_accounts_due_v834 TO authenticated;
CREATE OR REPLACE VIEW public.rr_accounts_latest_test_cycle_v846_1 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (WITH latest AS (
         SELECT rr_accounts_test_cycle_v846_1.test_code
           FROM rr_accounts_test_cycle_v846_1
          ORDER BY rr_accounts_test_cycle_v846_1.tested_at DESC, rr_accounts_test_cycle_v846_1.id DESC
         LIMIT 1
        )
 SELECT t.id,
    t.test_code,
    t.step_no,
    t.step_name,
    t.status,
    t.reference_no,
    t.reference_id,
    t.amount,
    t.qty,
    t.payload,
    t.tested_at
   FROM rr_accounts_test_cycle_v846_1 t
     JOIN latest l ON l.test_code = t.test_code
  ORDER BY t.step_no) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_acct_can_view_v805();
REVOKE ALL ON public.rr_accounts_latest_test_cycle_v846_1 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_accounts_latest_test_cycle_v846_1 TO authenticated;
CREATE OR REPLACE VIEW public.rr_accounts_latest_voucher_test_v847_2 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (WITH latest AS (
         SELECT rr_accounts_voucher_test_v847_2.test_code
           FROM rr_accounts_voucher_test_v847_2
          ORDER BY rr_accounts_voucher_test_v847_2.tested_at DESC, rr_accounts_voucher_test_v847_2.id DESC
         LIMIT 1
        )
 SELECT t.id,
    t.test_code,
    t.step_no,
    t.test_name,
    t.status,
    t.voucher_no,
    t.transaction_id,
    t.amount,
    t.detail,
    t.tested_at
   FROM rr_accounts_voucher_test_v847_2 t
     JOIN latest l ON l.test_code = t.test_code
  ORDER BY t.step_no) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_acct_can_view_v805();
REVOKE ALL ON public.rr_accounts_latest_voucher_test_v847_2 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_accounts_latest_voucher_test_v847_2 TO authenticated;
CREATE OR REPLACE VIEW public.rr_accounts_module_contract_v846 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT module_code,
    parent_module,
    workflow_code,
    canonical_backend,
    is_active
   FROM ( VALUES ('RECEIPT_PAYMENT'::text,'ACCOUNTS'::text,'RECEIPT_PAYMENT'::text,'rr_accounts_post_receipt_v805 / rr_accounts_post_payment_v805'::text,true), ('PURCHASE'::text,'ACCOUNTS'::text,'PURCHASE'::text,'rr_accounts_post_material_purchase_v805'::text,true), ('SALES'::text,'ACCOUNTS'::text,'SALES_PI_CPI'::text,'rr_fg_save_pi_v787'::text,true)) x(module_code, parent_module, workflow_code, canonical_backend, is_active)) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_acct_can_view_v805();
REVOKE ALL ON public.rr_accounts_module_contract_v846 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_accounts_module_contract_v846 TO authenticated;
CREATE OR REPLACE VIEW public.rr_accounts_operational_status_v846_1 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT count(*) FILTER (WHERE step_name = 'RECEIPT POST'::text AND status = 'PASS'::text) > 0 AS receipt_working,
    count(*) FILTER (WHERE step_name = 'PAYMENT POST'::text AND status = 'PASS'::text) > 0 AS payment_working,
    count(*) FILTER (WHERE step_name = 'PURCHASE POST'::text AND status = 'PASS'::text) > 0 AS purchase_working,
    count(*) FILTER (WHERE step_name = 'PI CREATE'::text AND status = 'PASS'::text) > 0 AS pi_create_working,
    count(*) FILTER (WHERE step_name = 'SAME PI EDIT'::text AND status = 'PASS'::text) > 0 AS pi_edit_working,
    count(*) FILTER (WHERE step_name = 'CPI FINAL'::text AND status = 'PASS'::text) > 0 AS cpi_final_working,
    count(*) FILTER (WHERE step_name = 'FULL OPERATIONAL FLOW'::text AND status = 'PASS'::text) > 0 AS full_cycle_working
   FROM rr_accounts_latest_test_cycle_v846_1) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_acct_can_view_v805();
REVOKE ALL ON public.rr_accounts_operational_status_v846_1 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_accounts_operational_status_v846_1 TO authenticated;
CREATE OR REPLACE VIEW public.rr_accounts_reporting_health_v806 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT ( SELECT count(*) AS count
           FROM rr_account_categories_v805 c
             LEFT JOIN rr_account_report_map_v806 rm ON rm.category_code = c.category_code
          WHERE c.is_active AND rm.category_code IS NULL) AS unmapped_category_count,
    ( SELECT count(*) AS count
           FROM rr_ledgers_v805 l
             JOIN rr_account_categories_v805 c ON c.id = l.category_id
             LEFT JOIN rr_account_report_map_v806 rm ON rm.category_code = c.category_code
          WHERE l.is_active AND rm.category_code IS NULL) AS unmapped_ledger_count,
    ( SELECT count(*) AS count
           FROM ( SELECT rr_account_postings_v805.transaction_id
                   FROM rr_account_postings_v805
                  GROUP BY rr_account_postings_v805.transaction_id
                 HAVING abs(COALESCE(sum(rr_account_postings_v805.dr_amount), 0::numeric) - COALESCE(sum(rr_account_postings_v805.cr_amount), 0::numeric)) > 0.01) x) AS unbalanced_transaction_count,
    ( SELECT count(*) AS count
           FROM rr_account_postings_v805 p
             LEFT JOIN rr_account_transactions_v805 t ON t.id = p.transaction_id
          WHERE t.id IS NULL) AS orphan_posting_count) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_acct_can_view_v805();
REVOKE ALL ON public.rr_accounts_reporting_health_v806 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_accounts_reporting_health_v806 TO authenticated;
CREATE OR REPLACE VIEW public.rr_accounts_test_example_ready_v846 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT ( SELECT count(*) AS count
           FROM rr_ledgers_v805
          WHERE COALESCE(rr_ledgers_v805.is_active, true) = true AND (upper(COALESCE(rr_ledgers_v805.ledger_kind, ''::text)) = ANY (ARRAY['CASH'::text, 'BANK'::text]))) AS cash_bank_ledgers,
    ( SELECT count(*) AS count
           FROM rr_ledgers_v805
          WHERE COALESCE(rr_ledgers_v805.is_active, true) = true AND (upper(COALESCE(rr_ledgers_v805.ledger_kind, ''::text)) <> ALL (ARRAY['CASH'::text, 'BANK'::text]))) AS party_ledgers,
    ( SELECT count(*) AS count
           FROM rr_material_master_v805
          WHERE COALESCE(rr_material_master_v805.is_active, true) = true) AS active_materials,
    ( SELECT count(*) AS count
           FROM rr_fg_stock_balance_v787
          WHERE rr_fg_stock_balance_v787.data_mode = 'TEST'::text AND COALESCE(rr_fg_stock_balance_v787.available_qty, 0) > 0) AS test_sale_stock_rows) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_acct_can_view_v805();
REVOKE ALL ON public.rr_accounts_test_example_ready_v846 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_accounts_test_example_ready_v846 TO authenticated;
CREATE OR REPLACE VIEW public.rr_accounts_voucher_health_v847_2 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT count(*) FILTER (WHERE test_name = 'RECEIPT AUTO VOUCHER'::text AND status = 'PASS'::text) > 0 AS receipt_pass,
    count(*) FILTER (WHERE test_name = 'PAYMENT AUTO VOUCHER'::text AND status = 'PASS'::text) > 0 AS payment_pass,
    count(*) FILTER (WHERE test_name = 'PURCHASE AUTO VOUCHER'::text AND status = 'PASS'::text) > 0 AS purchase_pass,
    count(*) FILTER (WHERE test_name = 'SALE AUTO VOUCHER'::text AND status = 'PASS'::text) > 0 AS sale_pass,
    count(*) FILTER (WHERE test_name = 'DUPLICATE SOURCE GUARD'::text AND status = 'PASS'::text) > 0 AS duplicate_guard_pass,
    count(*) FILTER (WHERE test_name = 'REAL LEGACY PREFLIGHT GATE'::text AND status = 'PASS'::text) > 0 AS real_gate_pass,
    count(*) FILTER (WHERE test_name = 'HISTORICAL VOUCHER PRESERVATION'::text AND status = 'PASS'::text) > 0 AS historical_preservation_pass,
    count(*) FILTER (WHERE test_name = 'FULL AUTO VOUCHER FLOW'::text AND status = 'PASS'::text) > 0 AS full_flow_pass
   FROM rr_accounts_latest_voucher_test_v847_2) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_acct_can_view_v805();
REVOKE ALL ON public.rr_accounts_voucher_health_v847_2 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_accounts_voucher_health_v847_2 TO authenticated;
CREATE OR REPLACE VIEW public.rr_ledgers_grouped_v819 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT m.group_code,
    m.group_name,
    m.natural_side,
    m.header_code,
    m.header_name,
    m.category_code,
    m.category_name,
    l.id AS ledger_id,
    l.ledger_code,
    l.ledger_name,
    l.ledger_kind,
    l.opening_balance,
    l.opening_side,
    l.is_active,
    m.group_order,
    m.header_order,
    m.category_order
   FROM rr_ledgers_v805 l
     JOIN rr_account_grouping_v819 m ON m.category_code = (( SELECT c.category_code
           FROM rr_account_categories_v805 c
          WHERE c.id = l.category_id))) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_acct_can_view_v805();
REVOKE ALL ON public.rr_ledgers_grouped_v819 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_ledgers_grouped_v819 TO authenticated;
CREATE OR REPLACE VIEW public.rr_payroll_adjustment_board_v778 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT a.id,
    a.worker_id,
    a.period_month,
    a.data_mode,
    a.adjustment_type,
    a.amount,
    a.reason,
    a.status,
    a.included_payroll_run_id,
    a.created_by,
    a.cancelled_by,
    a.cancelled_reason,
    a.created_at,
    a.cancelled_at,
    p.worker_name,
    p.worker_code,
    p.department_code
   FROM rr_payroll_adjustments_v778 a
     LEFT JOIN LATERAL ( SELECT x.worker_id,
            x.worker_code,
            x.worker_name,
            x.department_code,
            x.role_code,
            x.profile_id,
            x.worker_category,
            x.shift_id,
            x.shift_code,
            x.shift_name,
            x.duty_start,
            x.duty_end,
            x.normal_payable_minutes,
            x.lunch_is_paid,
            x.grace_in_minutes,
            x.minimum_presence_minutes,
            x.overtime_multiplier,
            x.holiday_multiplier,
            x.monthly_salary,
            x.attendance_required,
            x.late_deduction_applicable,
            x.overtime_applicable,
            x.holiday_extra_applicable,
            x.grace_offset_against_ot,
            x.exception_reason,
            x.piece_advance_percent,
            x.piece_advance_floor,
            x.salaried_advance_limit_type,
            x.salaried_advance_limit_value,
            x.advance_cycle,
            x.settlement_cycle,
            x.salary_advance_day,
            x.salary_due_day,
            x.claim_debit_timing,
            x.effective_from,
            x.effective_to,
            x.payroll_profile_status,
            x.data_mode,
            x.configured_at,
            x.configured_by,
            x.reason
           FROM rr_worker_payroll_board_v777_3 x
          WHERE x.worker_id = a.worker_id AND upper(COALESCE(x.data_mode, 'TEST'::text)) = a.data_mode
          ORDER BY x.effective_from DESC NULLS LAST
         LIMIT 1) p ON true) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_worker_salary_can_view_v781();
REVOKE ALL ON public.rr_payroll_adjustment_board_v778 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_payroll_adjustment_board_v778 TO authenticated;
CREATE OR REPLACE VIEW public.rr_payroll_claim_reserve_summary_v800 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT worker_id,
    max(worker_name) AS worker_name,
    COALESCE(sum(reserve_amount) FILTER (WHERE status = 'HELD'::text AND reserve_type = 'ALTER'::text), 0::numeric) AS alter_reserve,
    COALESCE(sum(reserve_amount) FILTER (WHERE status = 'HELD'::text AND reserve_type = 'MISSING'::text), 0::numeric) AS missing_reserve,
    COALESCE(sum(reserve_amount) FILTER (WHERE status = 'HELD'::text), 0::numeric) AS total_claim_reserve,
    COALESCE(sum(reserve_amount) FILTER (WHERE status = 'RELEASED'::text), 0::numeric) AS released_reserve,
    COALESCE(sum(reserve_amount) FILTER (WHERE status = 'CONVERTED_TO_FINAL_DEBIT'::text), 0::numeric) AS converted_final_debit
   FROM rr_payroll_claim_reserve_v800
  GROUP BY worker_id) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_worker_salary_can_view_v781();
REVOKE ALL ON public.rr_payroll_claim_reserve_summary_v800 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_payroll_claim_reserve_summary_v800 TO authenticated;
CREATE OR REPLACE VIEW public.rr_payroll_hold_amount_v800 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT id,
    reserve_code AS hold_code,
    worker_id,
    worker_name,
    reserve_type AS hold_type,
    source_id,
    canonical_lot_id,
    lot_no,
    department_code,
    assignment_id,
    colour_code,
    size_code,
    qty,
    frozen_rate,
    reserve_amount AS hold_amount,
    status AS hold_status,
    held_at,
    released_at,
    converted_at,
    created_by,
    payload
   FROM rr_payroll_claim_reserve_v800) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_worker_salary_can_view_v781();
REVOKE ALL ON public.rr_payroll_hold_amount_v800 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_payroll_hold_amount_v800 TO authenticated;
CREATE OR REPLACE VIEW public.rr_payroll_line_board_v778 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT l.id,
    l.payroll_run_id,
    l.worker_id,
    l.worker_name,
    l.department_code,
    l.payroll_profile_snapshot,
    l.shift_snapshot,
    l.monthly_salary,
    l.base_salary,
    l.employment_days,
    l.present_days,
    l.absent_days,
    l.half_days,
    l.paid_leave_days,
    l.unpaid_leave_days,
    l.weekly_off_days,
    l.holiday_days,
    l.holiday_work_days,
    l.incomplete_days,
    l.raw_late_minutes,
    l.deductible_late_minutes,
    l.raw_overtime_minutes,
    l.grace_offset_minutes,
    l.payable_overtime_minutes,
    l.absence_deduction,
    l.late_deduction,
    l.overtime_earning,
    l.holiday_extra_earning,
    l.adjustment_earning,
    l.adjustment_deduction,
    l.advance_deduction,
    l.gross_pay,
    l.total_deduction,
    l.net_pay,
    l.calculation_breakdown,
    l.created_at,
    r.period_month,
    r.period_end,
    r.data_mode,
    r.status AS run_status
   FROM rr_payroll_run_lines_v778 l
     JOIN rr_payroll_runs_v778 r ON r.id = l.payroll_run_id) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_worker_salary_can_view_v781();
REVOKE ALL ON public.rr_payroll_line_board_v778 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_payroll_line_board_v778 TO authenticated;
CREATE OR REPLACE VIEW public.rr_payroll_run_board_v778 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT id,
    period_month,
    period_end,
    data_mode,
    status,
    worker_count,
    incomplete_worker_count,
    gross_total,
    deduction_total,
    net_total,
    calculated_by,
    calculated_at,
    approved_by,
    approved_at,
    approval_reason,
    reopened_by,
    reopened_at,
    reopen_reason,
    paid_by,
    paid_at,
    payment_reference,
    created_at,
    updated_at,
        CASE
            WHEN status = ANY (ARRAY['APPROVED'::text, 'PAID'::text]) THEN true
            ELSE false
        END AS is_locked
   FROM rr_payroll_runs_v778 r) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_worker_salary_can_view_v781();
REVOKE ALL ON public.rr_payroll_run_board_v778 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_payroll_run_board_v778 TO authenticated;
CREATE OR REPLACE VIEW public.rr_salary_bulk_flow_board_v782 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT b.id AS batch_id,
    b.data_mode,
    b.cycle_type,
    b.payroll_category,
    b.period_month,
    b.earning_window_start,
    b.earning_window_end,
    b.payment_date,
    b.payment_mode,
    b.voucher_no,
    b.owner_payment_amount,
    b.eligible_total,
    b.liability_total,
    b.allocation_ratio,
    b.rounding_unit,
    b.worker_count,
    b.full_eligible_payment,
    b.status AS batch_status,
    b.remarks AS batch_remarks,
    b.created_at AS batch_created_at,
    l.id AS batch_line_id,
    l.worker_id,
    l.worker_name,
    l.worker_code,
    l.department_code,
    l.previous_outstanding,
    l.monthly_salary,
    l.earned_to_cutoff,
    l.first_week_earning,
    l.next_week_earning,
    l.eligible_current_amount,
    l.eligible_part_payment,
    l.part_payment,
    l.balance_after_part_payment,
    l.final_payable,
    l.final_payment,
    l.new_outstanding,
    l.allocated_amount,
    l.payable_pcs,
    l.missing_rate_rows,
    l.missing_cap_rows
   FROM rr_salary_bulk_batches_v782 b
     JOIN rr_salary_bulk_batch_lines_v782 l ON l.batch_id = b.id) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_worker_salary_can_view_v781();
REVOKE ALL ON public.rr_salary_bulk_flow_board_v782 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_salary_bulk_flow_board_v782 TO authenticated;
CREATE OR REPLACE VIEW public.rr_salary_bulk_flow_board_v782_2 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT b.id AS batch_id,
    b.data_mode,
    b.cycle_type,
    b.payroll_category,
    b.period_month,
    b.earning_window_start,
    b.earning_window_end,
    b.payment_date,
    b.payment_mode,
    b.voucher_no,
    b.owner_payment_amount,
    b.eligible_total,
    b.liability_total,
    b.allocation_ratio,
    b.rounding_unit,
    b.worker_count,
    b.full_eligible_payment,
    b.status AS batch_status,
    b.remarks AS batch_remarks,
    b.created_at AS batch_created_at,
    l.id AS batch_line_id,
    l.worker_id,
    l.worker_name,
    l.worker_code,
    l.department_code,
    l.payment_selected,
    l.previous_outstanding,
    l.pcs_window_days,
    l.pcs_window_earning,
    l.eligible_current_amount,
    l.eligible_part_payment,
    l.part_payment,
    l.balance_after_part_payment,
    l.final_payable,
    l.final_payment,
    l.new_outstanding,
    l.allocated_amount,
    l.payable_pcs,
    l.missing_rate_rows,
    l.missing_cap_rows
   FROM rr_salary_bulk_batches_v782 b
     JOIN rr_salary_bulk_batch_lines_v782 l ON l.batch_id = b.id) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_worker_salary_can_view_v781();
REVOKE ALL ON public.rr_salary_bulk_flow_board_v782_2 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_salary_bulk_flow_board_v782_2 TO authenticated;
CREATE OR REPLACE VIEW public.rr_salary_head_bind_v779 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT r.period_month,
    r.period_end,
    r.data_mode,
    'PIECE_RATE'::text AS payroll_category,
    'PCS_V779'::text AS source_module,
    r.id AS source_run_id,
    r.status AS run_status,
    l.worker_id,
    l.worker_name,
    l.worker_code,
    l.department_code,
    l.payable_qty AS production_qty,
    l.base_piece_earning AS base_amount,
    l.rate_enhancement_earning + l.monthly_flat_incentive + l.adjustment_earning AS incentive_amount,
    l.adjustment_deduction + l.advance_deduction AS deduction_amount,
    l.gross_pay AS gross_amount,
    l.net_pay AS net_amount,
    l.missing_rate_rows + l.missing_cap_rows + l.attendance_incomplete_days AS exception_count,
    r.status = ANY (ARRAY['APPROVED'::text, 'PARTIALLY_PAID'::text, 'PAID'::text]) AS is_locked,
    COALESCE(d.paid_amount, 0::numeric)::numeric(16,2) AS paid_amount,
    COALESCE(d.balance_amount, l.net_pay) AS balance_amount,
    COALESCE(d.payment_status, 'NOT_POSTED'::text) AS payment_status
   FROM rr_piece_payroll_run_lines_v779 l
     JOIN rr_piece_payroll_runs_v779 r ON r.id = l.piece_run_id
     LEFT JOIN rr_worker_salary_due_board_v781 d ON d.source_module = 'PCS_V779'::text AND d.source_run_id = l.piece_run_id AND d.source_line_id = l.id
  WHERE r.status = ANY (ARRAY['APPROVED'::text, 'PARTIALLY_PAID'::text, 'PAID'::text])) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_worker_salary_can_view_v781();
REVOKE ALL ON public.rr_salary_head_bind_v779 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_salary_head_bind_v779 TO authenticated;
CREATE OR REPLACE VIEW public.rr_salary_payment_history_v785 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT id,
    data_mode,
    payroll_category,
    payment_method,
    payment_scope,
    period_start,
    period_end,
    period_month,
    payment_date,
    payment_mode,
    voucher_no,
    remarks,
    eligible_worker_count,
    selected_worker_count,
    advance_worker_count,
    total_previous_outstanding,
    total_current_period_payable,
    total_final_payable,
    selected_scope_payable,
    bulk_amount_payment,
    total_outstanding_payment,
    total_current_period_payment,
    total_new_outstanding,
    allocation_ratio,
    rounding_unit,
    status,
    created_by,
    created_by_name,
    created_at,
    voided_by,
    voided_by_name,
    voided_at,
    void_reason,
    ( SELECT count(*) AS count
           FROM rr_worker_message_outbox_v785 o
          WHERE o.source_type = 'SALARY_PAYMENT_BATCH'::text AND o.source_id = b.id) AS mobile_message_count,
    ( SELECT count(*) AS count
           FROM rr_worker_app_notifications_v785 n
          WHERE n.source_type = 'SALARY_PAYMENT_BATCH'::text AND n.source_id = b.id) AS app_notification_count
   FROM rr_salary_payment_batches_v785 b) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_worker_salary_can_view_v781();
REVOKE ALL ON public.rr_salary_payment_history_v785 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_salary_payment_history_v785 TO authenticated;
CREATE OR REPLACE VIEW public.rr_salary_worker_balance_v782 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT data_mode,
    worker_id,
    (array_agg(worker_name ORDER BY created_at DESC) FILTER (WHERE NULLIF(TRIM(BOTH FROM worker_name), ''::text) IS NOT NULL))[1] AS worker_name,
    (array_agg(worker_code ORDER BY created_at DESC) FILTER (WHERE NULLIF(TRIM(BOTH FROM worker_code), ''::text) IS NOT NULL))[1] AS worker_code,
    (array_agg(department_code ORDER BY created_at DESC) FILTER (WHERE NULLIF(TRIM(BOTH FROM department_code), ''::text) IS NOT NULL))[1] AS department_code,
    sum(
        CASE
            WHEN status = 'POSTED'::text THEN balance_effect
            ELSE 0::numeric
        END)::numeric(16,2) AS ledger_balance,
    GREATEST(sum(
        CASE
            WHEN status = 'POSTED'::text THEN balance_effect
            ELSE 0::numeric
        END), 0::numeric)::numeric(16,2) AS outstanding_amount,
    GREATEST(- sum(
        CASE
            WHEN status = 'POSTED'::text THEN balance_effect
            ELSE 0::numeric
        END), 0::numeric)::numeric(16,2) AS advance_credit_amount,
    max(entry_date) FILTER (WHERE status = 'POSTED'::text AND (entry_type = ANY (ARRAY['PAYMENT'::text, 'BULK_PAYMENT'::text]))) AS last_payment_date,
    max(created_at) FILTER (WHERE status = 'POSTED'::text AND (entry_type = ANY (ARRAY['PAYMENT'::text, 'BULK_PAYMENT'::text]))) AS last_payment_at
   FROM rr_worker_salary_ledger_v781 l
  GROUP BY data_mode, worker_id) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_worker_salary_can_view_v781();
REVOKE ALL ON public.rr_salary_worker_balance_v782 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_salary_worker_balance_v782 TO authenticated;
CREATE OR REPLACE VIEW public.rr_worker_salary_balance_v781 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT data_mode,
    worker_id,
    max(worker_name) AS worker_name,
    max(worker_code) AS worker_code,
    max(department_code) AS department_code,
    sum(
        CASE
            WHEN status = 'POSTED'::text AND balance_effect > 0::numeric THEN balance_effect
            ELSE 0::numeric
        END)::numeric(16,2) AS total_due_credit,
    sum(
        CASE
            WHEN status = 'POSTED'::text AND balance_effect < 0::numeric THEN - balance_effect
            ELSE 0::numeric
        END)::numeric(16,2) AS total_payment_debit,
    sum(
        CASE
            WHEN status = 'POSTED'::text THEN balance_effect
            ELSE 0::numeric
        END)::numeric(16,2) AS balance_amount,
    max(entry_date) FILTER (WHERE status = 'POSTED'::text AND entry_type = 'PAYMENT'::text) AS last_payment_date,
    max(created_at) FILTER (WHERE status = 'POSTED'::text AND entry_type = 'PAYMENT'::text) AS last_payment_at
   FROM rr_worker_salary_ledger_v781 l
  GROUP BY data_mode, worker_id) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_worker_salary_can_view_v781();
REVOKE ALL ON public.rr_worker_salary_balance_v781 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_worker_salary_balance_v781 TO authenticated;
CREATE OR REPLACE VIEW public.rr_worker_salary_due_board_v781 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT d.id AS due_entry_id,
    d.data_mode,
    d.worker_id,
    d.worker_name,
    d.worker_code,
    d.department_code,
    d.payroll_category,
    d.source_module,
    d.source_run_id,
    d.source_line_id,
    d.period_month,
    d.entry_date AS due_date,
    d.amount AS due_amount,
    COALESCE(p.paid_amount, 0::numeric)::numeric(16,2) AS paid_amount,
    GREATEST(d.amount - COALESCE(p.paid_amount, 0::numeric), 0::numeric)::numeric(16,2) AS balance_amount,
        CASE
            WHEN COALESCE(p.paid_amount, 0::numeric) <= 0::numeric THEN 'UNPAID'::text
            WHEN (COALESCE(p.paid_amount, 0::numeric) + 0.005) < d.amount THEN 'PARTIAL'::text
            ELSE 'PAID'::text
        END AS payment_status,
    p.last_payment_at,
    p.payment_count,
    d.reference_no AS due_reference,
    d.remarks AS due_remarks,
    d.created_at AS due_created_at
   FROM rr_worker_salary_ledger_v781 d
     LEFT JOIN LATERAL ( SELECT COALESCE(sum(
                CASE
                    WHEN x.entry_type = 'PAYMENT'::text THEN x.amount
                    WHEN x.entry_type = 'PAYMENT_REVERSAL'::text THEN - x.amount
                    ELSE 0::numeric
                END), 0::numeric)::numeric(16,2) AS paid_amount,
            max(x.created_at) FILTER (WHERE x.entry_type = 'PAYMENT'::text) AS last_payment_at,
            count(*) FILTER (WHERE x.entry_type = 'PAYMENT'::text)::integer AS payment_count
           FROM rr_worker_salary_ledger_v781 x
          WHERE x.due_entry_id = d.id AND x.status = 'POSTED'::text AND (x.entry_type = ANY (ARRAY['PAYMENT'::text, 'PAYMENT_REVERSAL'::text]))) p ON true
  WHERE d.status = 'POSTED'::text AND d.entry_type = 'SALARY_DUE'::text) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_worker_salary_can_view_v781();
REVOKE ALL ON public.rr_worker_salary_due_board_v781 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_worker_salary_due_board_v781 TO authenticated;
CREATE OR REPLACE VIEW public.rr_worker_salary_ledger_accounts_v9786 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT s.id,
    s.data_mode,
    COALESCE(a.canonical_worker_id, s.worker_id) AS worker_id,
    s.worker_name,
    s.worker_code,
    s.department_code,
    s.payroll_category,
    s.source_module,
    s.source_run_id,
    s.source_line_id,
    s.period_month,
    s.entry_date,
    s.entry_type,
    s.amount,
    s.balance_effect,
    s.due_entry_id,
    s.related_entry_id,
    s.payment_mode,
    s.reference_no,
    s.remarks,
    s.status,
    s.created_by,
    s.created_by_name,
    s.created_at,
    s.voided_by,
    s.voided_by_name,
    s.voided_at,
    s.void_reason,
    s.source_key,
    s.bulk_batch_id,
    s.bulk_line_id,
    s.earning_window_start,
    s.earning_window_end
   FROM rr_worker_salary_ledger_v781 s
     LEFT JOIN rr_salary_worker_alias_v9786 a ON a.legacy_worker_id = s.worker_id) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_worker_salary_can_view_v781();
REVOKE ALL ON public.rr_worker_salary_ledger_accounts_v9786 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_worker_salary_ledger_accounts_v9786 TO authenticated;
CREATE OR REPLACE VIEW public.rr_worker_salary_ledger_board_v781 WITH(security_barrier=true) AS
SELECT protected_rows.* FROM (SELECT id,
    data_mode,
    worker_id,
    worker_name,
    worker_code,
    department_code,
    payroll_category,
    source_module,
    source_run_id,
    source_line_id,
    period_month,
    entry_date,
    entry_type,
    amount,
    balance_effect,
    due_entry_id,
    related_entry_id,
    payment_mode,
    reference_no,
    remarks,
    status,
    created_by,
    created_by_name,
    created_at,
    voided_by,
    voided_by_name,
    voided_at,
    void_reason,
        CASE
            WHEN status <> 'POSTED'::text THEN 0::numeric
            WHEN balance_effect > 0::numeric THEN balance_effect
            ELSE 0::numeric
        END::numeric(16,2) AS due_or_credit_amount,
        CASE
            WHEN status <> 'POSTED'::text THEN 0::numeric
            WHEN balance_effect < 0::numeric THEN - balance_effect
            ELSE 0::numeric
        END::numeric(16,2) AS payment_or_debit_amount,
    sum(
        CASE
            WHEN status = 'POSTED'::text THEN balance_effect
            ELSE 0::numeric
        END) OVER (PARTITION BY data_mode, worker_id ORDER BY entry_date, created_at, id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)::numeric(16,2) AS running_balance
   FROM rr_worker_salary_ledger_v781 l) protected_rows
WHERE auth.uid() IS NOT NULL AND public.rr_worker_salary_can_view_v781();
REVOKE ALL ON public.rr_worker_salary_ledger_board_v781 FROM PUBLIC,anon;
GRANT SELECT ON public.rr_worker_salary_ledger_board_v781 TO authenticated;
ALTER TABLE public.rr_account_book_hidden_pairs_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_account_book_hidden_pairs_v1 FROM PUBLIC,anon,authenticated;
COMMIT;

