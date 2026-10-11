'use strict';
const assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../real-matching-cloth-master-v9235.js'),'utf8');
function fixture(role='super_admin',mode='TEST'){
 const elements=new Map(),calls=[];
 const el=id=>{if(!elements.has(id))elements.set(id,{value:'',dataset:{},classList:{add(){},remove(){},contains(){return false}},textContent:'',innerHTML:'',reset(){},focus(){},querySelectorAll(){return []}});return elements.get(id)};
 const client={from(){},rpc:async name=>{calls.push({name});return {data:name.includes('options')?[]:{card:null,fabrics:[]},error:null}}};
 const win={RRFinancialRequests:{rpc:async(c,name,payload)=>{calls.push({name,payload});return {data:{purchase_id:'one'},error:null}}}};
 const ctx={window:win,document:{getElementById:el},Intl,Date,Number,String,URLSearchParams,location:{search:''},console:{error(){},warn(){}},setTimeout(){},Promise};
 vm.runInNewContext(source.replace('boot();','window.__mcTest={state,save};'),ctx);
 const state=win.__mcTest.state;Object.assign(state,{client,role,dataMode:mode,newFabricMode:true,newVendorMode:true});
 for(const [id,value]of Object.entries({mcNewFabric:'TEST FABRIC',mcVendor:'TEST VENDOR',mcBillNo:'B1',mcBillQty:'2',mcBillRate:'2',mcBillValue:'4',mcBillDate:'2026-10-11',mcRemarks:'test'}))el(id).value=value;
 return {run:()=>win.__mcTest.save({preventDefault(){}}),calls,el};
}
(async()=>{
 const f=fixture();await f.run();
 const post=f.calls.find(x=>x.name==='rr_post_mc_purchase_accounts_test71');assert.ok(post,'Super Admin must submit the protected purchase');assert.equal(post.payload.p_data_mode,'TEST');assert.equal(post.payload.p_bill_qty,2);assert.equal(post.payload.p_supplier_ledger_id,null);
 assert.ok(!f.calls.some(x=>/rr_post_mc_fabric_purchase_v[23]/.test(x.name)),'Legacy stock-only fallback must not run');
 const bad=fixture('owner','REAL');await bad.run();assert.ok(!bad.calls.some(x=>x.payload),'REAL mode must not use TEST purchase path');
 const worker=fixture('worker');await worker.run();assert.equal(worker.calls.length,0,'Worker must not post purchase');
 console.log('PASS: MC1 form routes Super Admin through atomic TEST request; worker/REAL denied; no legacy fallback');
})().catch(e=>{console.error(e);process.exitCode=1});
