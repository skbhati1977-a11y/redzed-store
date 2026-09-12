const fs=require('fs'),assert=require('assert');
const sql=fs.readFileSync('supabase/migrations/20260910184500_test69_rci_sales_reversal_bridge_v9762.sql','utf8');
assert.match(sql,/rr\.trusted_account_bridge/);
assert.match(sql,/rci_reversal/);
assert.match(sql,/rr_accounts_reverse_source_mirror_v806/);
assert.doesNotMatch(sql,/role_code.*sales/i);
console.log('TEST69 scoped RCI Sales reversal bridge V9762: PASS');
