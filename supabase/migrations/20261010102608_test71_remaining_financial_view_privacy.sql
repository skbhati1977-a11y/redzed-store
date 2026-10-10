-- Close remaining anonymous financial views; preserve scoped worker rows where supported.
CREATE OR REPLACE VIEW public.rr_advance_payment_history_v785 WITH (security_barrier=true) AS SELECT protected_rows.* FROM (SELECT id,
    data_mode,
    payroll_category_filter,
    payment_date,
    payment_mode,
    voucher_no,
    remarks,
    worker_count,
    existing_advance_total,
    new_advance_payment_total,
    updated_advance_total,
    status,
    created_by,
    created_by_name,
    created_at,
    ( SELECT count(*) AS count
           FROM rr_worker_message_outbox_v785 o
          WHERE o.source_type = 'ADVANCE_PAYMENT_BATCH'::text AND o.source_id = b.id) AS mobile_message_count,
    ( SELECT count(*) AS count
           FROM rr_worker_app_notifications_v785 n
          WHERE n.source_type = 'ADVANCE_PAYMENT_BATCH'::text AND n.source_id = b.id) AS app_notification_count
   FROM rr_advance_payment_batches_v785 b) protected_rows WHERE auth.uid() IS NOT NULL AND (public.rr_worker_salary_can_view_v781());
REVOKE ALL ON public.rr_advance_payment_history_v785 FROM PUBLIC, anon;
GRANT SELECT ON public.rr_advance_payment_history_v785 TO authenticated;
CREATE OR REPLACE VIEW public.rr_committee_accounts_reconcile_v825 WITH (security_barrier=true) AS SELECT protected_rows.* FROM (SELECT s.id AS scheme_id,
    s.scheme_code,
    s.scheme_name,
    s.data_mode,
    count(p.id) FILTER (WHERE p.status = 'POSTED'::text) AS active_payments,
    round(COALESCE(sum(p.amount) FILTER (WHERE p.status = 'POSTED'::text), 0::numeric), 2) AS committee_paid,
    count(p.id) FILTER (WHERE p.status = 'POSTED'::text AND p.accounts_transaction_id IS NOT NULL) AS accounts_posted_payments,
    round(COALESCE(sum(p.amount) FILTER (WHERE p.status = 'POSTED'::text AND p.accounts_transaction_id IS NOT NULL), 0::numeric), 2) AS accounts_linked_amount,
    count(p.id) FILTER (WHERE p.status = 'REVERSED'::text) AS reversed_payments,
    count(p.id) FILTER (WHERE p.status = 'POSTED'::text AND p.accounts_transaction_id IS NULL) AS accounts_pending_payments
   FROM rr_committee_schemes_v820 s
     LEFT JOIN rr_committee_payments_v824 p ON p.scheme_id = s.id
  GROUP BY s.id, s.scheme_code, s.scheme_name, s.data_mode) protected_rows WHERE auth.uid() IS NOT NULL AND (public.rr_acct_can_view_v805());
REVOKE ALL ON public.rr_committee_accounts_reconcile_v825 FROM PUBLIC, anon;
GRANT SELECT ON public.rr_committee_accounts_reconcile_v825 TO authenticated;
CREATE OR REPLACE VIEW public.rr_committee_member_account_v821 WITH (security_barrier=true) AS SELECT protected_rows.* FROM (SELECT o.id AS organizer_id,
    o.organizer_code,
    o.organizer_name,
    o.mobile AS organizer_mobile,
    s.id AS scheme_id,
    s.scheme_code,
    s.scheme_name,
    s.chit_amount,
    s.member_count AS total_members_months,
    s.gross_installment,
    s.our_member_no,
    s.our_win_month,
    s.start_date,
    s.status,
    s.data_mode,
    count(m.id) AS scheduled_months,
    COALESCE(sum(m.our_dividend_share), 0::numeric) AS total_dividend_benefit,
    COALESCE(sum(m.our_net_installment), 0::numeric) AS total_net_installment_due,
    COALESCE(sum(m.our_paid_amount), 0::numeric) AS total_paid,
    COALESCE(sum(
        CASE
            WHEN m.our_payment_status = 'PENDING'::text THEN m.our_net_installment
            ELSE 0::numeric
        END), 0::numeric) AS installment_outstanding,
    COALESCE(sum(
        CASE
            WHEN m.prize_status = 'POSTED'::text THEN m.our_prize_received
            ELSE 0::numeric
        END), 0::numeric) AS prize_received,
    COALESCE(max(
        CASE
            WHEN m.month_no = s.our_win_month THEN m.auction_discount
            ELSE 0::numeric
        END), 0::numeric) AS our_winning_discount,
    round(COALESCE(sum(
        CASE
            WHEN m.prize_status = 'POSTED'::text THEN m.our_prize_received
            ELSE 0::numeric
        END), 0::numeric) - COALESCE(sum(m.our_paid_amount), 0::numeric), 2) AS member_cash_profit_loss,
    round(COALESCE(sum(m.our_dividend_share), 0::numeric) - COALESCE(max(
        CASE
            WHEN m.month_no = s.our_win_month THEN m.auction_discount
            ELSE 0::numeric
        END), 0::numeric), 2) AS member_accounting_profit_loss
   FROM rr_committee_schemes_v820 s
     JOIN rr_committee_organizers_v821 o ON o.id = s.organizer_id
     LEFT JOIN rr_committee_months_v820 m ON m.scheme_id = s.id
  WHERE s.member_side_only = true
  GROUP BY o.id, s.id) protected_rows WHERE auth.uid() IS NOT NULL AND (public.rr_acct_can_view_v805());
REVOKE ALL ON public.rr_committee_member_account_v821 FROM PUBLIC, anon;
GRANT SELECT ON public.rr_committee_member_account_v821 TO authenticated;
CREATE OR REPLACE VIEW public.rr_cpi_accounts_audit_v847 WITH (security_barrier=true) AS SELECT protected_rows.* FROM (SELECT p.id AS cpi_id,
    p.pi_no,
    p.cpi_no,
    p.grand_total,
    p.data_mode,
    l.buyer_name,
    l.customer_ledger_id,
    l.sales_ledger_id,
    l.account_transaction_id,
    l.account_voucher_no,
    COALESCE(l.status, 'NOT_EVALUATED'::text) AS account_status,
    l.message
   FROM rr_fg_pi_v787 p
     LEFT JOIN rr_cpi_accounts_link_v847 l ON l.cpi_id = p.id
  WHERE p.status = 'CI_FINAL'::text) protected_rows WHERE auth.uid() IS NOT NULL AND (public.rr_acct_can_view_v805());
REVOKE ALL ON public.rr_cpi_accounts_audit_v847 FROM PUBLIC, anon;
GRANT SELECT ON public.rr_cpi_accounts_audit_v847 TO authenticated;
CREATE OR REPLACE VIEW public.rr_damage_claim_due_v845_6 WITH (security_barrier=true) AS SELECT protected_rows.* FROM (SELECT 'CLAIM'::text AS module_code,
    'ACCOUNTS'::text AS department_code,
    'DAMAGE_CLAIM_DUE'::text AS due_type,
    id::text AS source_id,
    COALESCE(lot_no, damage_no::text) AS reference_no,
    concat_ws(' · '::text, particular_label, reason, claim_status) AS reference_detail,
    round(COALESCE(damage_qty, 0::numeric), 1) AS due_qty,
    round(COALESCE(claim_value, 0::numeric), 1) AS due_amount,
    created_at::timestamp without time zone AS due_since,
    COALESCE(NULLIF(claim_status, ''::text), 'PENDING'::text) AS due_state,
    COALESCE(updated_at, created_at)::timestamp without time zone AS sort_at,
    jsonb_build_object('damage_no', damage_no, 'cb_id', cb_id, 'lot_no', lot_no, 'damage_stage', damage_stage, 'damage_qty', damage_qty, 'reason', reason, 'claim_value', claim_value, 'claim_status', claim_status, 'owner_approved_at', owner_approved_at, 'cost_deduction_posted', cost_deduction_posted) AS payload
   FROM rr_product_damage_claims c
  WHERE COALESCE(cost_deduction_posted, false) = false AND (upper(COALESCE(claim_status, 'PENDING'::text)) <> ALL (ARRAY['CLOSED'::text, 'COMPLETED'::text, 'COMPLETE'::text, 'CANCELLED'::text, 'REJECTED'::text, 'REVERSED'::text, 'POSTED'::text, 'SETTLED'::text, 'PAID'::text]))) protected_rows WHERE auth.uid() IS NOT NULL AND (public.rr_worker_salary_can_view_v781());
REVOKE ALL ON public.rr_damage_claim_due_v845_6 FROM PUBLIC, anon;
GRANT SELECT ON public.rr_damage_claim_due_v845_6 TO authenticated;
CREATE OR REPLACE VIEW public.rr_piece_payroll_detail_board_v779 WITH (security_barrier=true) AS SELECT protected_rows.* FROM (SELECT d.id,
    d.piece_run_id,
    d.worker_id,
    d.source_key,
    d.source_view,
    d.assignment_id,
    d.canonical_lot_id,
    d.lot_no,
    d.department_code,
    d.to_department_code,
    d.colour_code,
    d.colour_name,
    d.size_code,
    d.assigned_cap_qty,
    d.submitted_before_qty,
    d.submitted_to_end_qty,
    d.payable_qty,
    d.base_rate,
    d.rate_source,
    d.enhancement_type,
    d.enhancement_value,
    d.enhanced_rate,
    d.base_amount,
    d.enhancement_amount,
    d.mapping_status,
    d.first_source_at,
    d.last_source_at,
    d.source_snapshot,
    d.created_at,
    p.worker_name,
    p.worker_code
   FROM rr_piece_payroll_details_v779 d
     LEFT JOIN LATERAL ( SELECT x.worker_name,
            x.worker_code
           FROM rr_worker_payroll_board_v777_3 x
          WHERE x.worker_id = d.worker_id
          ORDER BY x.effective_from DESC NULLS LAST
         LIMIT 1) p ON true) protected_rows WHERE auth.uid() IS NOT NULL AND (public.rr_worker_salary_can_view_v781() OR protected_rows.worker_id::text = nullif(public.rr_upm_effective_identity_v200()->>'worker_id',''));
REVOKE ALL ON public.rr_piece_payroll_detail_board_v779 FROM PUBLIC, anon;
GRANT SELECT ON public.rr_piece_payroll_detail_board_v779 TO authenticated;
CREATE OR REPLACE VIEW public.rr_piece_payroll_line_board_v779 WITH (security_barrier=true) AS SELECT protected_rows.* FROM (SELECT l.id,
    l.piece_run_id,
    l.worker_id,
    l.worker_name,
    l.worker_code,
    l.department_code,
    l.payroll_profile_snapshot,
    l.leadership_snapshot,
    l.compensation_mode,
    l.payable_qty,
    l.average_base_rate,
    l.base_piece_earning,
    l.rate_enhancement_earning,
    l.monthly_flat_incentive,
    l.adjustment_earning,
    l.adjustment_deduction,
    l.advance_deduction,
    l.damage_reference_rows,
    l.damage_reference_amount,
    l.attendance_present_days,
    l.attendance_absent_days,
    l.attendance_half_days,
    l.attendance_incomplete_days,
    l.missing_rate_rows,
    l.missing_cap_rows,
    l.gross_pay,
    l.total_deduction,
    l.net_pay,
    l.calculation_breakdown,
    l.created_at,
    r.period_month,
    r.period_end,
    r.data_mode,
    r.status AS run_status,
    d.due_entry_id,
    COALESCE(d.due_amount, 0::numeric)::numeric(16,2) AS ledger_due_amount,
    COALESCE(d.paid_amount, 0::numeric)::numeric(16,2) AS ledger_paid_amount,
    COALESCE(d.balance_amount, 0::numeric)::numeric(16,2) AS ledger_balance_amount,
    COALESCE(d.payment_status, 'NOT_POSTED'::text) AS ledger_payment_status,
    d.last_payment_at AS ledger_last_payment_at
   FROM rr_piece_payroll_run_lines_v779 l
     JOIN rr_piece_payroll_runs_v779 r ON r.id = l.piece_run_id
     LEFT JOIN rr_worker_salary_due_board_v781 d ON d.source_module = 'PCS_V779'::text AND d.source_run_id = l.piece_run_id AND d.source_line_id = l.id) protected_rows WHERE auth.uid() IS NOT NULL AND (public.rr_worker_salary_can_view_v781() OR protected_rows.worker_id::text = nullif(public.rr_upm_effective_identity_v200()->>'worker_id',''));
REVOKE ALL ON public.rr_piece_payroll_line_board_v779 FROM PUBLIC, anon;
GRANT SELECT ON public.rr_piece_payroll_line_board_v779 TO authenticated;
CREATE OR REPLACE VIEW public.rr_piece_payroll_run_board_v779 WITH (security_barrier=true) AS SELECT protected_rows.* FROM (SELECT r.id,
    r.period_month,
    r.period_end,
    r.data_mode,
    r.status,
    r.worker_count,
    r.incomplete_worker_count,
    r.total_payable_qty,
    r.gross_total,
    r.deduction_total,
    r.net_total,
    r.calculated_by,
    r.calculated_at,
    r.approved_by,
    r.approved_at,
    r.approval_reason,
    r.reopened_by,
    r.reopened_at,
    r.reopen_reason,
    r.paid_by,
    r.paid_at,
    r.payment_reference,
    r.created_at,
    r.updated_at,
    r.status = ANY (ARRAY['APPROVED'::text, 'PARTIALLY_PAID'::text, 'PAID'::text]) AS is_locked,
    COALESCE(x.ledger_due_total, 0::numeric)::numeric(16,2) AS ledger_due_total,
    COALESCE(x.ledger_paid_total, 0::numeric)::numeric(16,2) AS ledger_paid_total,
    COALESCE(x.ledger_balance_total, 0::numeric)::numeric(16,2) AS ledger_balance_total,
        CASE
            WHEN COALESCE(x.ledger_due_total, 0::numeric) <= 0::numeric THEN 'NOT_POSTED'::text
            WHEN COALESCE(x.ledger_balance_total, 0::numeric) <= 0.005 THEN 'PAID'::text
            WHEN COALESCE(x.ledger_paid_total, 0::numeric) > 0.005 THEN 'PARTIAL'::text
            ELSE 'UNPAID'::text
        END AS ledger_payment_status
   FROM rr_piece_payroll_runs_v779 r
     LEFT JOIN LATERAL ( SELECT sum(d.due_amount) AS ledger_due_total,
            sum(d.paid_amount) AS ledger_paid_total,
            sum(d.balance_amount) AS ledger_balance_total
           FROM rr_worker_salary_due_board_v781 d
          WHERE d.source_module = 'PCS_V779'::text AND d.source_run_id = r.id) x ON true) protected_rows WHERE auth.uid() IS NOT NULL AND (public.rr_worker_salary_can_view_v781());
REVOKE ALL ON public.rr_piece_payroll_run_board_v779 FROM PUBLIC, anon;
GRANT SELECT ON public.rr_piece_payroll_run_board_v779 TO authenticated;
CREATE OR REPLACE VIEW public.rr_printing_team_salary_per_pc_v404 WITH (security_barrier=true) AS SELECT protected_rows.* FROM (SELECT l.data_mode,
    l.canonical_lot_id,
    l.lot_no,
    l.department_code,
    l.salaried_labor_cost,
    r.total_qty AS canonical_lot_qty,
    round(
        CASE
            WHEN COALESCE(r.total_qty, 0::numeric) > 0::numeric THEN l.salaried_labor_cost / r.total_qty
            ELSE 0::numeric
        END, 4) AS salary_cost_per_pc
   FROM rr_upm_department_labor_cost_v9160 l
     JOIN rr_upm_lot_registry r ON r.canonical_lot_id = l.canonical_lot_id
  WHERE l.department_code = 'PRINTING'::text) protected_rows WHERE auth.uid() IS NOT NULL AND (public.rr_worker_salary_can_view_v781());
REVOKE ALL ON public.rr_printing_team_salary_per_pc_v404 FROM PUBLIC, anon;
GRANT SELECT ON public.rr_printing_team_salary_per_pc_v404 TO authenticated;
CREATE OR REPLACE VIEW public.rr_product_damage_claim_details_v1 WITH (security_barrier=true) AS SELECT protected_rows.* FROM (SELECT d.id,
    d.damage_no,
    d.cb_id,
    d.division_id,
    d.purchase_entry_id,
    d.purchase_roll_id,
    d.damage_stage,
    d.lot_no,
    d.damage_qty,
    d.rate_snapshot,
    d.claim_value,
    d.damage_date,
    d.reason,
    d.remarks,
    d.particular_label,
    d.admin_phone,
    d.admin_message,
    d.admin_message_sent_at,
    d.admin_message_sent_by,
    d.admin_decision_note,
    d.admin_verified_at,
    d.admin_verified_by,
    d.vendor_phone,
    d.vendor_message,
    d.vendor_message_sent_at,
    d.vendor_message_sent_by,
    d.claim_status,
    d.inventory_deducted,
    d.cost_deduction_posted,
    d.created_at,
    d.created_by,
    d.updated_at,
    fp.cb_no,
    COALESCE(u.cb_code, concat('D', u.division_index)) AS division_code,
    pe.vendor_name,
    pe.vendor_bill_no,
    pe.bill_date,
    pe.fabric_name,
    r.roll_no,
    COALESCE(( SELECT jsonb_agg(to_jsonb(m.*) ORDER BY m.created_at) AS jsonb_agg
           FROM rr_product_damage_media m
          WHERE m.claim_id = d.id), '[]'::jsonb) AS media
   FROM rr_product_damage_claims d
     JOIN rr_fabric_purchases fp ON fp.id = d.cb_id
     JOIN rr_cb_units u ON u.id = d.division_id
     JOIN rr_cb_purchase_entries pe ON pe.id = d.purchase_entry_id
     LEFT JOIN rr_cb_purchase_rolls r ON r.id = d.purchase_roll_id) protected_rows WHERE auth.uid() IS NOT NULL AND (public.rr_worker_salary_can_view_v781());
REVOKE ALL ON public.rr_product_damage_claim_details_v1 FROM PUBLIC, anon;
GRANT SELECT ON public.rr_product_damage_claim_details_v1 TO authenticated;
CREATE OR REPLACE VIEW public.rr_purchase_accounts_audit_v847 WITH (security_barrier=true) AS SELECT protected_rows.* FROM (SELECT p.id AS purchase_id,
    p.bill_no,
    p.total_value,
    p.data_mode,
    t.id AS account_transaction_id,
    t.voucher_no,
        CASE
            WHEN t.id IS NOT NULL THEN 'POSTED'::text
            ELSE 'MISSING_ACCOUNT_POST'::text
        END AS account_status
   FROM rr_material_purchases_v805 p
     LEFT JOIN rr_account_transactions_v805 t ON t.source_module = 'MATERIAL_PURCHASE_V805'::text AND t.source_record_id = p.id::text AND t.data_mode = p.data_mode AND t.status <> 'REVERSED'::text) protected_rows WHERE auth.uid() IS NOT NULL AND (public.rr_acct_can_view_v805());
REVOKE ALL ON public.rr_purchase_accounts_audit_v847 FROM PUBLIC, anon;
GRANT SELECT ON public.rr_purchase_accounts_audit_v847 TO authenticated;
CREATE OR REPLACE VIEW public.rr_worker_advance_balance_v785 WITH (security_barrier=true) AS SELECT protected_rows.* FROM (WITH dedicated AS (
         SELECT a.data_mode,
            a.worker_id,
            GREATEST(COALESCE(sum(
                CASE
                    WHEN a.status = 'POSTED'::text THEN a.balance_effect
                    ELSE 0::numeric
                END), 0::numeric), 0::numeric)::numeric(16,2) AS dedicated_advance_balance,
            (array_agg(a.worker_name ORDER BY a.created_at DESC) FILTER (WHERE NULLIF(TRIM(BOTH FROM a.worker_name), ''::text) IS NOT NULL))[1] AS worker_name,
            (array_agg(a.worker_code ORDER BY a.created_at DESC) FILTER (WHERE NULLIF(TRIM(BOTH FROM a.worker_code), ''::text) IS NOT NULL))[1] AS worker_code,
            (array_agg(a.department_code ORDER BY a.created_at DESC) FILTER (WHERE NULLIF(TRIM(BOTH FROM a.department_code), ''::text) IS NOT NULL))[1] AS department_code,
            (array_agg(a.payroll_category ORDER BY a.created_at DESC) FILTER (WHERE NULLIF(TRIM(BOTH FROM a.payroll_category), ''::text) IS NOT NULL))[1] AS payroll_category
           FROM rr_worker_advance_ledger_v785 a
          GROUP BY a.data_mode, a.worker_id
        ), latest_profile AS (
         SELECT DISTINCT ON ((upper(COALESCE(p_1.data_mode, 'TEST'::text))), p_1.worker_id) upper(COALESCE(p_1.data_mode, 'TEST'::text)) AS data_mode,
            p_1.worker_id,
            p_1.worker_name,
            p_1.worker_code,
            p_1.department_code,
                CASE
                    WHEN rr_piece_category_normalize_v779(p_1.worker_category) = 'PIECE_RATE'::text THEN 'PIECE_RATE'::text
                    ELSE upper(COALESCE(p_1.worker_category, 'UNKNOWN'::text))
                END AS payroll_category
           FROM rr_worker_payroll_board_v777_3 p_1
          ORDER BY (upper(COALESCE(p_1.data_mode, 'TEST'::text))), p_1.worker_id, p_1.effective_from DESC NULLS LAST
        ), universe AS (
         SELECT b_1.data_mode,
            b_1.worker_id
           FROM rr_salary_worker_balance_v782 b_1
          WHERE b_1.advance_credit_amount > 0.005
        UNION
         SELECT d_1.data_mode,
            d_1.worker_id
           FROM dedicated d_1
          WHERE d_1.dedicated_advance_balance > 0.005
        )
 SELECT u.data_mode,
    u.worker_id,
    COALESCE(NULLIF(TRIM(BOTH FROM p.worker_name), ''::text), NULLIF(TRIM(BOTH FROM d.worker_name), ''::text), b.worker_name, u.worker_id::text) AS worker_name,
    COALESCE(NULLIF(TRIM(BOTH FROM p.worker_code), ''::text), NULLIF(TRIM(BOTH FROM d.worker_code), ''::text), b.worker_code) AS worker_code,
    COALESCE(NULLIF(TRIM(BOTH FROM p.department_code), ''::text), NULLIF(TRIM(BOTH FROM d.department_code), ''::text), b.department_code) AS department_code,
    COALESCE(NULLIF(TRIM(BOTH FROM p.payroll_category), ''::text), NULLIF(TRIM(BOTH FROM d.payroll_category), ''::text), 'UNKNOWN'::text) AS payroll_category,
    COALESCE(b.advance_credit_amount, 0::numeric)::numeric(16,2) AS legacy_advance_balance,
    COALESCE(d.dedicated_advance_balance, 0::numeric)::numeric(16,2) AS dedicated_advance_balance,
    (COALESCE(b.advance_credit_amount, 0::numeric) + COALESCE(d.dedicated_advance_balance, 0::numeric))::numeric(16,2) AS total_advance_balance
   FROM universe u
     LEFT JOIN rr_salary_worker_balance_v782 b ON b.data_mode = u.data_mode AND b.worker_id = u.worker_id
     LEFT JOIN dedicated d ON d.data_mode = u.data_mode AND d.worker_id = u.worker_id
     LEFT JOIN latest_profile p ON p.data_mode = u.data_mode AND p.worker_id = u.worker_id
  WHERE (COALESCE(b.advance_credit_amount, 0::numeric) + COALESCE(d.dedicated_advance_balance, 0::numeric)) > 0.005) protected_rows WHERE auth.uid() IS NOT NULL AND (public.rr_worker_salary_can_view_v781() OR protected_rows.worker_id::text = nullif(public.rr_upm_effective_identity_v200()->>'worker_id',''));
REVOKE ALL ON public.rr_worker_advance_balance_v785 FROM PUBLIC, anon;
GRANT SELECT ON public.rr_worker_advance_balance_v785 TO authenticated;
CREATE OR REPLACE VIEW public.rr_worker_claim_money_summary_v800 WITH (security_barrier=true) AS SELECT protected_rows.* FROM (WITH h AS (
         SELECT rr_payroll_hold_amount_v800.worker_id,
            max(rr_payroll_hold_amount_v800.worker_name) AS worker_name,
            COALESCE(sum(rr_payroll_hold_amount_v800.hold_amount) FILTER (WHERE rr_payroll_hold_amount_v800.hold_status = 'HELD'::text AND rr_payroll_hold_amount_v800.hold_type = 'ALTER'::text), 0::numeric) AS alter_hold_amount,
            COALESCE(sum(rr_payroll_hold_amount_v800.hold_amount) FILTER (WHERE rr_payroll_hold_amount_v800.hold_status = 'HELD'::text AND rr_payroll_hold_amount_v800.hold_type = 'MISSING'::text), 0::numeric) AS missing_hold_amount,
            COALESCE(sum(rr_payroll_hold_amount_v800.hold_amount) FILTER (WHERE rr_payroll_hold_amount_v800.hold_status = 'HELD'::text), 0::numeric) AS total_hold_amount,
            COALESCE(sum(rr_payroll_hold_amount_v800.hold_amount) FILTER (WHERE rr_payroll_hold_amount_v800.hold_status = 'RELEASED'::text), 0::numeric) AS released_hold_amount
           FROM rr_payroll_hold_amount_v800
          GROUP BY rr_payroll_hold_amount_v800.worker_id
        ), d AS (
         SELECT rr_worker_final_claim_deduction_v800.worker_id,
            max(rr_worker_final_claim_deduction_v800.worker_name) AS worker_name,
            COALESCE(sum(rr_worker_final_claim_deduction_v800.final_claim_deduction), 0::numeric) AS total_final_claim_deduction
           FROM rr_worker_final_claim_deduction_v800
          GROUP BY rr_worker_final_claim_deduction_v800.worker_id
        )
 SELECT COALESCE(h.worker_id, d.worker_id) AS worker_id,
    COALESCE(h.worker_name, d.worker_name) AS worker_name,
    COALESCE(h.alter_hold_amount, 0::numeric) AS alter_hold_amount,
    COALESCE(h.missing_hold_amount, 0::numeric) AS missing_hold_amount,
    COALESCE(h.total_hold_amount, 0::numeric) AS total_hold_amount,
    COALESCE(h.released_hold_amount, 0::numeric) AS released_hold_amount,
    COALESCE(d.total_final_claim_deduction, 0::numeric) AS total_final_claim_deduction
   FROM h
     FULL JOIN d USING (worker_id)) protected_rows WHERE auth.uid() IS NOT NULL AND (public.rr_worker_salary_can_view_v781() OR protected_rows.worker_id::text = nullif(public.rr_upm_effective_identity_v200()->>'worker_id',''));
REVOKE ALL ON public.rr_worker_claim_money_summary_v800 FROM PUBLIC, anon;
GRANT SELECT ON public.rr_worker_claim_money_summary_v800 TO authenticated;
CREATE OR REPLACE VIEW public.rr_worker_final_claim_deduction_v800 WITH (security_barrier=true) AS SELECT protected_rows.* FROM (SELECT id,
    debit_code AS final_claim_code,
    worker_id,
    worker_name,
    debit_type AS final_claim_type,
    source_id,
    canonical_lot_id,
    lot_no,
    department_code,
    assignment_id,
    colour_code,
    size_code,
    qty,
    frozen_rate,
    debit_amount AS final_claim_deduction,
    posted_at,
    created_by,
    payload
   FROM rr_worker_claim_debit_v800) protected_rows WHERE auth.uid() IS NOT NULL AND (public.rr_worker_salary_can_view_v781() OR protected_rows.worker_id::text = nullif(public.rr_upm_effective_identity_v200()->>'worker_id',''));
REVOKE ALL ON public.rr_worker_final_claim_deduction_v800 FROM PUBLIC, anon;
GRANT SELECT ON public.rr_worker_final_claim_deduction_v800 TO authenticated;
CREATE OR REPLACE VIEW public.rr_worker_payroll_board_v777_3 WITH (security_barrier=true) AS SELECT protected_rows.* FROM (WITH latest AS (
         SELECT DISTINCT ON (p_1.worker_id, p_1.data_mode) p_1.profile_id,
            p_1.worker_id,
            p_1.worker_category,
            p_1.shift_id,
            p_1.monthly_salary,
            p_1.weekly_holiday_isodow,
            p_1.attendance_required,
            p_1.late_deduction_applicable,
            p_1.overtime_applicable,
            p_1.holiday_extra_applicable,
            p_1.grace_offset_against_ot,
            p_1.exception_reason,
            p_1.piece_advance_percent,
            p_1.piece_advance_floor,
            p_1.salaried_advance_limit_type,
            p_1.salaried_advance_limit_value,
            p_1.advance_cycle,
            p_1.settlement_cycle,
            p_1.salary_advance_day,
            p_1.salary_due_day,
            p_1.claim_debit_timing,
            p_1.effective_from,
            p_1.effective_to,
            p_1.status,
            p_1.data_mode,
            p_1.configured_at,
            p_1.configured_by,
            p_1.reason
           FROM rr_worker_payroll_profile_v777_2 p_1
          ORDER BY p_1.worker_id, p_1.data_mode, (p_1.status = 'ACTIVE'::text) DESC, p_1.effective_from DESC, p_1.configured_at DESC
        )
 SELECT w.worker_id,
    w.worker_code,
    w.worker_name,
    w.department_code,
    w.role_code,
    p.profile_id,
    p.worker_category,
    p.shift_id,
    s.shift_code,
    s.shift_name,
    s.duty_start,
    s.duty_end,
    s.normal_payable_minutes,
    s.lunch_is_paid,
    s.grace_in_minutes,
    s.minimum_presence_minutes,
    s.overtime_multiplier,
    s.holiday_multiplier,
    p.monthly_salary,
    p.attendance_required,
    p.late_deduction_applicable,
    p.overtime_applicable,
    p.holiday_extra_applicable,
    p.grace_offset_against_ot,
    p.exception_reason,
    p.piece_advance_percent,
    p.piece_advance_floor,
    p.salaried_advance_limit_type,
    p.salaried_advance_limit_value,
    p.advance_cycle,
    p.settlement_cycle,
    p.salary_advance_day,
    p.salary_due_day,
    p.claim_debit_timing,
    p.effective_from,
    p.effective_to,
    p.status AS payroll_profile_status,
    p.data_mode,
    p.configured_at,
    p.configured_by,
    p.reason
   FROM rr_worker_directory_unified_v1 w
     LEFT JOIN latest p ON p.worker_id = w.worker_id
     LEFT JOIN rr_shift_master_v777_2 s ON s.shift_id = p.shift_id) protected_rows WHERE auth.uid() IS NOT NULL AND (public.rr_worker_salary_can_view_v781() OR protected_rows.worker_id::text = nullif(public.rr_upm_effective_identity_v200()->>'worker_id',''));
REVOKE ALL ON public.rr_worker_payroll_board_v777_3 FROM PUBLIC, anon;
GRANT SELECT ON public.rr_worker_payroll_board_v777_3 TO authenticated;
DO $acl$ DECLARE r record;BEGIN FOR r IN SELECT c.relname FROM pg_class c WHERE c.relnamespace='public'::regnamespace AND c.relkind='r' AND c.relname ~ '(claim|advance|salary|payroll|account)' LOOP EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC, anon',r.relname);END LOOP;END $acl$;
