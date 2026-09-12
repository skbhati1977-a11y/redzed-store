"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs");
const js=fs.readFileSync("test70-worker-accounts-map-v78.js","utf8");
const sql=fs.readFileSync("supabase/migrations/20260912153000_test70_worker_accounts_chat_mapping_v78.sql","utf8");
for(const token of ["rr_test70_worker_accounts_map_v78","worker_id","salary_ledger_id","rr_worker_accounts_map_v9785","rr_worker_real_chat_map_v9787","STAFF_ACCESS_REQUIRED","revoke all","to authenticated"])assert.ok(sql.includes(token),`missing secure mapping ${token}`);
for(const token of ["rr_test70_worker_accounts_map_v78","data-person","Salary Ledger mapped","Salary &amp; Wages Ledger","ledger_id="])assert.ok(js.includes(token),`missing TEST70 worker UI mapping ${token}`);
assert.ok(!sql.includes("worker_name=m.worker_name"),"worker mapping must not resolve by name");
console.log("PASS: TEST70 worker chat uses canonical Salary ledger mapping.");
