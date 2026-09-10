"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs");
const html=fs.readFileSync("real-role-permission-v777-4-final.html","utf8"),js=fs.readFileSync("real-role-permission-v777-4-final.js","utf8"),edge=fs.readFileSync("supabase/functions/rr-owner-user-admin/index.ts","utf8");
assert.match(html,/z-index:2147483100/);assert.match(html,/overscroll-behavior:contain/);assert.match(html,/backface-visibility:hidden/);
assert.match(js,/data-edit-user-role/);assert.match(js,/action:"set_role"/);
assert.match(edge,/Only Owner can change primary roles/);assert.match(edge,/auth\.admin\.createUser/);assert.match(edge,/auth\.admin\.updateUserById/);
console.log("TEST69 V9754 Admin login creation and mobile header checks passed");
