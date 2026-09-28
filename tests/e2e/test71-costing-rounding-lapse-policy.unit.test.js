const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');
const round=fs.readFileSync('supabase/migrations/20260928140000_test71_universal_costing_rounding_v675.sql','utf8');
const actual=fs.readFileSync('supabase/migrations/20260928141000_test71_actual_product_cost_v679.sql','utf8');
test('costing uses half-rupee component and whole-rupee final rounding',()=>{assert.match(round,/round\(p_amount\*2\)\/2/);assert.match(round,/round\(p_amount\)/);});
test('actual product cost excludes lapse and general overhead',()=>{assert.match(actual,/oldbase-lapse-oh/);assert.match(actual,/lapse_product_cost_impact',0/);assert.match(actual,/general_overhead_product_cost_impact',0/);assert.match(actual,/OWNER MARGIN REMAINS COMMERCIAL BUFFER/);});
