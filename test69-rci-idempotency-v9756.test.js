"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs");
const sql=fs.readFileSync("supabase/migrations/20260910143000_test69_rci_idempotency_replay_v9756.sql","utf8");
assert.match(sql,/pg_advisory_xact_lock/);
assert.match(sql,/data_mode=v_mode and idempotency_key=v_key/);
assert.match(sql,/'idempotent_replay',true/);
assert.match(sql,/if v_existing\.id is not null then/);
console.log("TEST69 V9756 RCI idempotency replay checks passed");
