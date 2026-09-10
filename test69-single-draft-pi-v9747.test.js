"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs");
const sql=fs.readFileSync("supabase/migrations/20260910123000_test69_single_draft_pi_per_requirement_v9747.sql","utf8");
assert.match(sql,/row_number\(\) over\(partition by market_requirement_id order by created_at desc,id desc\)/);
assert.match(sql,/set status='CANCELLED'/);
assert.match(sql,/create unique index if not exists rr_fg_pi_one_draft_per_requirement_v9747/);
assert.match(sql,/where market_requirement_id is not null and status='DRAFT'/);
console.log('TEST69 V9747 single draft PI per requirement gate checks passed');
