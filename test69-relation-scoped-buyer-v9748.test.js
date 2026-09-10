"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs");
const sql=fs.readFileSync("supabase/migrations/20260910124500_test69_relation_scoped_buyer_split_v9748.sql","utf8");
assert.match(sql,/m\.source_kind='DISTRIBUTOR_CUSTOMER'/);
assert.match(sql,/x\.buyer_id=m\.buyer_id and x\.id<>m\.id/);
assert.match(sql,/set buyer_id=v_new_buyer,match_basis='CREATED'/);
assert.match(sql,/DC-'\|\|left\(r\.id::text,8\)/);
assert.match(sql,/create unique index if not exists rr_customer_sales_map_one_source_buyer_v9748/);
console.log('TEST69 V9748 relation-scoped buyer isolation checks passed');
