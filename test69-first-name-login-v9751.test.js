"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs");
const sql=fs.readFileSync("supabase/migrations/20260910134500_test69_first_name_department_login_v9751.sql","utf8");
assert.match(sql,/split_part\(trim\(full_name\),' ',1\) first_name/);
assert.match(sql,/v_candidate:=v_base\|\|'\.'\|\|v_n/);
assert.match(sql,/split_part\(trim\(new\.full_name\),' ',1\)/);
assert.match(sql,/commit;/);
assert.doesNotMatch(sql,/rollback;/);
console.log("TEST69 V9751 first-name.department login checks passed");
