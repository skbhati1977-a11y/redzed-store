const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');
const v402=fs.readFileSync('supabase/migrations/20260928115500_test71_split_payroll_salary_pools_v402.sql','utf8');
const v403=fs.readFileSync('supabase/migrations/20260928120000_test71_salary_final_authority_v403.sql','utf8');
const v404=fs.readFileSync('supabase/migrations/20260928121500_test71_final_cost_payroll_reconciled_v404.sql','utf8');
test('salary pools split production team from staff support',()=>{assert.match(v402,/production_team_payroll/);assert.match(v402,/staff_support_payroll/);assert.match(v402,/net_payable_salary/);assert.match(v402,/EACH POOL CAPPED/);});
test('final salary authority requires reconciled payroll',()=>{assert.match(v403,/rr_costing_salary_reconciliation_v402/);assert.match(v403,/final_actual_salary_cost/);});
test('final costing replaces legacy lapse staff once and blocks provisional completion',()=>{assert.match(v404,/newls-oldls/);assert.match(v404,/salary_final_actual/);assert.match(v404,/costing_complete.*final_actual_salary_cost/);assert.match(v404,/REPLACED ONCE/);});
