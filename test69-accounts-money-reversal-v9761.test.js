const fs=require('fs'),assert=require('assert');
const sql=fs.readFileSync('supabase/migrations/20260910183000_test69_accounts_money_reversal_v9761.sql','utf8');
assert.match(sql,/ACCOUNTS_TEMPLATE/);
assert.match(sql,/rr_accounts_reverse_transaction_v9761/);
assert.match(sql,/Only manual Receipt\/Payment can be reversed here/);
assert.match(sql,/rr_accounts_reverse_source_mirror_v806/);
assert.doesNotMatch(sql,/delete\s+from\s+public\.rr_account_transactions_v805/i);
console.log('TEST69 Accounts Receipt/Payment reversal V9761: PASS');
