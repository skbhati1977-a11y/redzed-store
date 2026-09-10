"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs");
const sql=fs.readFileSync("supabase/migrations/20260910130000_test69_distributor_customer_id_identity_v9749.sql","utf8");
assert.match(sql,/v_kind='REDZED_CUSTOMER' and v_buyer is null and length\(v_mobile\)=10/);
assert.match(sql,/v_kind='REDZED_CUSTOMER' and v_buyer is null then/);
assert.match(sql,/v_name\|\|' · DC-'\|\|left\(p_source_id::text,8\)/);
assert.doesNotMatch(sql,/if v_buyer is null and length\(v_mobile\)=10/);
assert.match(sql,/partner_customer_id=p_source_id/);
console.log('TEST69 V9749 distributor customer ID identity checks passed');
