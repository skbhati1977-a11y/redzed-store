const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {JSDOM}=require('jsdom');const {webcrypto}=require('node:crypto');
async function page({loggedIn=true,failFirst=false,malformed=false}={}){
 const dom=new JSDOM(fs.readFileSync('test71-import-preflight.html','utf8'),{url:'https://test.example/test71-import-preflight.html',runScripts:'outside-only'}),w=dom.window,calls=[];
 Object.defineProperty(w,'crypto',{value:webcrypto});w.TextDecoder=TextDecoder;
 w.supabaseClient={auth:{getUser:async()=>({data:{user:loggedIn?{id:'admin-1'}:null}})},rpc:async(name,args)=>{calls.push({name,args});if(failFirst&&calls.length===1)return {error:{message:'offline'}};return {data:malformed?{}:{batch_id:'source-batch',data_mode:'TEST',cleared_for_import:false,business_records_posted:0,findings:[]}};}};
 w.eval(fs.readFileSync('test71-source-intake.js','utf8'));w.eval(fs.readFileSync('test71-import-preflight.js','utf8'));
 const input=w.document.getElementById('sourceFile'),content=JSON.stringify([{module:'CUSTOMERS',source_key:'001',record_date:'2025-03-15',evidence_status:'KNOWN',values:{name:'Sample'},references:[]}]);
 Object.defineProperty(input,'files',{value:[{name:'source.json',size:content.length,arrayBuffer:async()=>new TextEncoder().encode(content).buffer}]});
 await input.onchange();return {dom,w,calls};
}
test('preparation only inspects; repeated taps stage once and never post business data',async()=>{
 const h=await page();try{
 assert.equal(h.calls.length,0);const b=h.w.document.getElementById('stageSource');await Promise.all([b.onclick(),b.onclick()]);
 assert.equal(h.calls.length,1);assert.equal(h.calls[0].name,'rr_import_stage_source_test71');assert.match(h.calls[0].args.p_source_sha256,/^[0-9a-f]{64}$/);
 assert.equal(h.calls[0].args.p_rows[0].source_key,'001');assert.match(h.w.document.getElementById('state').textContent,/Business posting: 0/);
 }finally{h.dom.window.close();}
});
test('network retry preserves original request ID; anonymous session calls no staging RPC',async()=>{
 const h=await page({failFirst:true});try{const b=h.w.document.getElementById('stageSource');await b.onclick();assert.match(h.w.document.getElementById('state').textContent,/offline/);await b.onclick();assert.equal(h.calls[0].args.p_request_id,h.calls[1].args.p_request_id);}finally{h.dom.window.close();}
 const anon=await page({loggedIn:false});try{await anon.w.document.getElementById('stageSource').onclick();assert.equal(anon.calls.length,0);assert.match(anon.w.document.getElementById('state').textContent,/login required/);}finally{anon.dom.window.close();}
});
test('missing server confirmation does not appear as successful staging',async()=>{
 const h=await page({malformed:true});try{await h.w.document.getElementById('stageSource').onclick();assert.match(h.w.document.getElementById('state').textContent,/confirmation missing/);assert.doesNotMatch(h.w.document.getElementById('state').textContent,/save हुआ/);}finally{h.dom.window.close();}
});
