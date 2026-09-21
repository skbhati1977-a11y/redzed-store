"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs");
const sql=fs.readFileSync("supabase/migrations/20260916001000_test70_custody_missing_owner_mirror_v185.sql","utf8");
const dept=fs.readFileSync("real-upm-department-view-v789.js","utf8");
const confirm=fs.readFileSync("real-upm-submit-confirm-v796.js","utf8");
for(const text of [
  "rr_upm_ready_to_assign_with_custody_v185","custody_line_man_id","ASSIGN_RECEIPT",
  "SUBMIT_COUNT","WORKER_CLAIM_PENDING","PACKING_SUBMITTED","rr_upm_missing_packing_finalize_v185",
  "rr_upm_submit_claim_v185","rr_upm_packing_claim_finalize_v185","rr_real_chat_work_inbox_v78"
])assert.ok(sql.includes(text),`Missing V185 custody contract: ${text}`);
for(const text of ["SAVING CUSTODY…","rr_upm_ready_to_assign_shared_v205"])
  assert.ok(dept.includes(text),`Missing App/Chat assignment mirror: ${text}`);
for(const text of ["RECEIVE GOODS","ACCEPT & COUNT","rr_upm_accept_physical_count_batch_v802"])
  assert.ok(confirm.includes(text),`Missing receipt/count UI: ${text}`);
console.log("PASS: V185 custody owner and Packing-held missing claims are mirrored.");
