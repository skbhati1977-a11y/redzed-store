const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {effectiveRows}=require('../../test71-costing-mapping.js');
const root=path.resolve(__dirname,'../..');
const read=name=>fs.readFileSync(path.join(root,name),'utf8');
const row=(id,method,date,scope={})=>({id,material_id:'material',consumption_method:method,effective_from:date,is_active:true,...scope});

test('current mapping loads instead of a future scheduled rule',()=>{
 const current=row('current','WORKER_ACTUAL','2026-09-27',{consume_department_code:'PACKING'});
 const future=row('future','WORKER_ACTUAL','2029-01-01',{consume_department_code:'PACKING'});
 assert.deepEqual(effectiveRows([future,current],'2026-10-04'),[current]);
});
test('exact duplicate scopes resolve once while distinct departments and ALL/category rules remain',()=>{
 const old=row('old','WORKER_ACTUAL','2026-09-27',{consume_department_code:'PACKING',updated_at:'2026-09-27T10:00:00Z'});
 const latest={...old,id:'latest',updated_at:'2026-09-27T11:00:00Z'};
 const press=row('press','WORKER_ACTUAL','2026-09-27',{consume_department_code:'PRESS'});
 const all=row('all','BOM_AUTO','2026-09-27',{category_code:'ALL',qty_per_piece:1});
 const cat=row('cat','BOM_AUTO','2026-09-27',{category_code:'SELF-COLLAR',qty_per_piece:2});
 const result=effectiveRows([old,latest,press,all,cat],'2026-10-04');
 assert.equal(result.length,4);assert.ok(!result.includes(old));
 for(const retained of [latest,press,all,cat])assert.ok(result.includes(retained));
});
test('inactive rules never become the current edit form',()=>{
 assert.deepEqual(effectiveRows([{...row('inactive','BOM_AUTO','2026-09-27'),is_active:false}],'2026-10-04'),[]);
});
test('CB opens the existing costing master, legacy URL retains view and return, master opens BOM',()=>{
 const cb=read('real-cb-new-v9130-fix2.html'),master=read('real-material-master-v805.js'),redirect=read('real-material-master-v853.html');
 assert.ok(cb.includes("await flushFieldAutosave();const target=new URL('real-material-master-v805.html'"));
 assert.ok(cb.includes("target.searchParams.set('view','costing-mapping')"));
 assert.ok(master.includes('await openBom()'));
 assert.ok(master.includes('window.RRCostingMapping.effectiveRows(allRows,today)'));
 assert.ok(redirect.includes('target.search=location.search;target.hash=location.hash'));
});
test('compatibility migration preserves existing salary, Gatta/Panni, tape and final-cost engines',()=>{
 const sql=read('supabase/migrations/20261004104436_test71_cb_costing_mapping_authority.sql');
 for(const name of ['rr_bom_material_aggregate_v701','rr_bom_gatta_panni_context_v684','rr_bom_gatta_rule_v681','rr_kandhi_tape_bom_cost_v700','rr_upm_product_cost_actual_v703','rr_costing_salary_allocation_v400','rr_lot_inherit_cb_set_combo_v1'])
  assert.doesNotMatch(sql,new RegExp('create or replace function public\\.'+name+'\\(','i'));
 assert.ok(sql.includes("v_cat:=upper(public.rr_lot_category_canonical_v682(p_canonical_lot_id)->>'category_code')"));
 assert.ok(sql.includes("upper(x.category_code)='ALL' or upper(x.category_code)=v_cat"));
 assert.ok(sql.includes("origin:='LOT_ART_SNAPSHOT'"));
});
