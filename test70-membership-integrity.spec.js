"use strict";
const assert=require("node:assert/strict"),test=require("node:test"),fs=require("node:fs"),vm=require("node:vm");

function validateDirectory(payload){
  assert.equal(payload.departments.length,18,"global owner must receive all canonical departments");
  const codes=new Set();
  for(const d of payload.departments){
    assert.ok(!codes.has(d.department_code),`duplicate department ${d.department_code}`);codes.add(d.department_code);
    assert.equal(d.worker_count,d.workers.length,`${d.department_code} worker count mismatch`);
    assert.equal(d.staff_count,d.staff.length,`${d.department_code} staff count mismatch`);
    assert.equal(new Set(d.workers.map(x=>x.worker_id)).size,d.workers.length,`${d.department_code} duplicate worker`);
    assert.equal(new Set(d.staff.map(x=>x.worker_id)).size,d.staff.length,`${d.department_code} duplicate staff`);
    for(const w of d.workers){assert.equal(w.membership_side,"WORKER");assert.equal(w.home_department_code,d.department_code)}
    for(const s of d.staff){assert.equal(s.membership_side,"STAFF");assert.ok(["UNIVERSAL_REDZED_STAFF","NAMED_CROSS_DEPARTMENT_STAFF"].includes(s.source_rule))}
  }
}

test("real directory count and cross-department invariants reject inconsistent payloads",()=>{
  const departments=Array.from({length:18},(_,i)=>({department_code:`D${i}`,worker_count:1,staff_count:1,workers:[{worker_id:`w${i}`,membership_side:"WORKER",home_department_code:`D${i}`}],staff:[{worker_id:"admin",membership_side:"STAFF",source_rule:"UNIVERSAL_REDZED_STAFF"}]}));
  validateDirectory({departments});
  departments[4].worker_count=2;
  assert.throws(()=>validateDirectory({departments}),/worker count mismatch/);
});

test("mobile scroll and nested history contracts are executable",()=>{
  const html=fs.readFileSync("test70-cb-purchase-real-chat-pilot.html","utf8"),js=fs.readFileSync("test70-real-chat-live-v70.js","utf8");
  assert.match(html,/\.scroll\{[^}]*overflow-y:auto/);
  assert.match(html,/\.messages\{[^}]*overflow:auto/);
  assert.match(html,/padding-bottom:max\(110px,calc\(env\(safe-area-inset-bottom\) \+ 72px\)\)/);
  assert.match(js,/history\.pushState\(\{view:'department',department:id\}/);
  assert.match(js,/history\.pushState\(\{view:'chat',kind,id,parentDepartment:parent\}/);
  assert.match(js,/state\?\.view==='department'.*openDepartment\(state\.department,false\)/);
});
