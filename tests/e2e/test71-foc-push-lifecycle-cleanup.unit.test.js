const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const p='supabase/migrations/20260928154500_test71_cleanup_v698_v716_manifest.sql';const s=fs.readFileSync(p,'utf8');
test('FOC policy and product-cost authority locked',()=>{for(const x of ['FOC V705','5.50/pc','V709','exactly once'])assert.match(s,new RegExp(x.replace('.','\\.')));});
test('push routes and identity locked',()=>{for(const x of ['V712','V713','V714','Targeted web push V708'])assert.match(s,new RegExp(x));});
test('legacy lifecycle RPCs converge',()=>{assert.match(s,/V327\/V328 -> V690/);assert.match(s,/finalize V327 -> V689/);});
