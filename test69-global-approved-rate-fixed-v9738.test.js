"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");

const sql = fs.readFileSync(
  "supabase/migrations/20260909104000_fix_pi_discount_compounding_global_v9738.sql",
  "utf8"
);

assert.match(sql, /drop trigger if exists rrq_pi_cpi_rate_change_v9300/,
  "The PI-line trigger that mutated approved rates must be removed");
assert.doesNotMatch(sql, /set final_sale_rate=new\.final_rate/,
  "A PI final rate must never become the next approved rate");
assert.match(sql, /x\.event_type='PACKING_ADMIN'/,
  "Legacy restoration must use the last explicit Packing/Admin decision");
assert.match(sql, /PI_RATE_COMPOUNDING_REPAIR_V9738/,
  "Legacy balance repair must be idempotently audited");
assert.match(sql, /set balance=b\.balance-r\.bad_delta/,
  "Draft PI effects must be reversed from RRQ balance");

console.log("TEST69 fixed approved-rate/one-time-discount v9738 checks passed");
