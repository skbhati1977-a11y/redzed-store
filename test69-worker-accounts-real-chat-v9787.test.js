"use strict";
const assert=require("node:assert/strict");
const fs=require("node:fs");
const sql=fs.readFileSync("supabase/migrations/20260912070000_test69_worker_accounts_real_chat_v9787.sql","utf8");
const accounts=fs.readFileSync("real-accounts-v805.js","utf8");
const lists=fs.readFileSync("real-chat-relation-lists-v9704.js","utf8");
for(const token of [
  "rr_worker_real_chat_map_v9787","WORKER_DIRECT","rr_accounts_party_chat_v9787",
  "rr_accounts_party_upload_v9787","rr_customer_chat_worker_members_v9439",
  "Account privacy lock","enable row level security"
]) assert.ok(sql.includes(token),`missing worker chat control: ${token}`);
assert.ok(sql.includes("return public.rr_accounts_party_chat_v9776"),"customer share flow must remain unchanged");
assert.ok(accounts.includes('rr_accounts_party_chat_v9787'),"Accounts must resolve worker-aware locked chat");
assert.ok(accounts.includes('rr_accounts_party_upload_v9787'),"Accounts must use worker-aware locked upload");
assert.ok(lists.includes('data-relation-filter="WORKER_DIRECT">WORKERS'),"Real Chat must have a separate Workers tab");
assert.ok(lists.includes('row.dataset.relation !== mode'),"relation tabs must isolate worker chats");
console.log("V9787 worker ledger locked Real Chat mapping: PASS");
