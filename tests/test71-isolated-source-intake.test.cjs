const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {JSDOM}=require('jsdom');
const {webcrypto}=require('node:crypto');
function page(rpc){
 const dom=new JSDOM(fs.readFileSync('test71-isolated-source-intake.html','utf8'),{url:'https://example.test/test71-isolated-source-intake.html',runScripts:'outside-only'});
 const w=dom.window;Object.defineProperty(w,'crypto',{value:webcrypto});w.TextDecoder=TextDecoder;
 w.supabaseClient={auth:{getUser:async()=>({data:{user:{id:'test-user'}}})},rpc};
 w.eval(fs.readFileSync('test71-source-intake.js','utf8'));w.eval(fs.readFileSync('test71-isolated-source-intake.js','utf8'));
 return w;
}
const dataset='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',batch='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
async function file(w){const bytes=Buffer.from(JSON.stringify([{module:'OPENING_GL',source_key:'cash',record_date:'2026-10-01',evidence_status:'ZERO',values:{ledger_key:'cash',debit:'0',credit:'0'},references:[]}])) ;Object.defineProperty(w.document.getElementById('sourceFile'),'files',{value:[{name:'source.json',size:bytes.length,arrayBuffer:async()=>bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength)}],configurable:true});await w.document.getElementById('sourceFile').onchange();}
test('source is sent only to selected isolated dataset and exact retry keeps request',async()=>{
 const calls=[];const w=page(async(name,args)=>{calls.push({name,args});return {data:{dataset_id:args.p_dataset_id,batch_id:batch,cleared_for_import:false,business_records_posted:0}};});
 w.document.getElementById('datasetId').value=dataset;await file(w);await w.document.getElementById('stageSource').onclick();await w.document.getElementById('stageSource').onclick();
 assert.equal(calls.length,2);assert(calls.every(c=>c.name==='rr_dataset_import_stage_test71'&&c.args.p_dataset_id===dataset));assert.equal(calls[0].args.p_request_id,calls[1].args.p_request_id);assert.match(w.document.getElementById('state').textContent,/Business posting 0/);w.close();
});
test('cross-dataset or business-posted confirmation cannot report success',async()=>{const w=page(async()=>({data:{dataset_id:'cccccccc-cccc-4ccc-8ccc-cccccccccccc',batch_id:batch,cleared_for_import:false,business_records_posted:0}}));w.document.getElementById('datasetId').value=dataset;await file(w);await w.document.getElementById('stageSource').onclick();assert.match(w.document.getElementById('state').textContent,/पुष्टि नहीं मिली/);w.close();});
test('dataset create is confirmed TEST and non-operational before selecting it',async()=>{const w=page(async()=>({data:{dataset_id:dataset,data_mode:'REAL',operational_posting_enabled:true}}));w.document.getElementById('datasetName').value='October';await w.document.getElementById('createDataset').onclick();assert.equal(w.document.getElementById('datasetId').value,'');assert.match(w.document.getElementById('state').textContent,/पुष्टि नहीं मिली/);w.close();});
test('missing login prevents any source write',async()=>{let calls=0;const w=page(async()=>{calls++;});w.supabaseClient.auth.getUser=async()=>({data:{user:null}});w.document.getElementById('datasetId').value=dataset;await file(w);await w.document.getElementById('stageSource').onclick();assert.equal(calls,0);assert.match(w.document.getElementById('state').textContent,/login चाहिए/);w.close();});
