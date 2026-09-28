const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');
const split=fs.readFileSync('supabase/migrations/20260928120000_test71_salary_final_authority_v403.sql','utf8');
const reconcile=fs.readFileSync('supabase/migrations/20260928114500_test71_payroll_costing_reconciliation_v401.sql','utf8');
test('payroll remains salary authority and costing is allocation only',()=>{assert.match(reconcile,/PAYROLL NET PAYABLE IS AUTHORITY|PAYROLL DECIDES PAYABLE SALARY/);assert.match(reconcile,/net_payable_salary/);assert.doesNotMatch(split,/update\s+public\.rr_monthly_payroll/i);});
test('final salary costing requires reconciled monthly payroll',()=>{assert.match(split,/rr_costing_salary_reconciliation_v402/);assert.match(split,/final_actual_salary_cost/);assert.match(split,/FINAL ACTUAL COSTING REQUIRES MONTH-MATCHED PAYROLL/);});
