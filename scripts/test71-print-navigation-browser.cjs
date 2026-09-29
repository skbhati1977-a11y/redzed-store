'use strict';
// Isolated browser regression: real HTML and runtime, mocked external I/O only.
// No credentials, network calls, or durable Supabase writes are used by this suite.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {chromium} = require(process.env.TEST71_PLAYWRIGHT_PATH || 'playwright');
const root=path.resolve(__dirname,'..');
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const noScripts=html=>html.replace(/<script\b[^>]*>[\s\S]*?<\/script\s*>/gi,'');
const results=[];
let browser;
async function pageFor(file){
  const page=await browser.newPage({viewport:{width:412,height:915}});
  await page.route('**/*',route=>route.fulfill({status:200,contentType:route.request().url().endsWith('.css')?'text/css':'text/html',body:route.request().url().includes('/case.html')?noScripts(read(file)):''}));
  await page.setContent(noScripts(read(file)).replace(/<link\b[^>]*href="([^"]+\.css)(?:\?[^"]*)?"[^>]*>/gi,(_,css)=>'<style>'+read(css)+'</style>'));
  await page.evaluate(()=>{const values=new Map();Object.defineProperty(window,'sessionStorage',{value:{getItem:k=>values.get(k)??null,setItem:(k,v)=>values.set(k,String(v)),removeItem:k=>values.delete(k)}});});
  return page;
}
async function run(name,fn){await fn();results.push({name,pass:true});console.log('PASS '+name);}
async function printPage(){
  const p=await pageFor('real-print-master.html');
  p.on('pageerror',e=>console.error('PAGE ERROR',e.message));
  await p.evaluate(()=>{
    if(!crypto.randomUUID){let unitId=0;crypto.randomUUID=()=> '00000000-0000-4000-8000-'+String(++unitId).padStart(12,'0');}
    const db=window.__printDb={masters:[],frames:[],media:{},writes:[],rpcCalls:[],failFrames:0,holdFrames:false};
    window.RR={safeText:v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])),requireOwner:async()=>({}),getMediaMap:async()=>db.media,
      uploadMedia:async({entityId})=>{const m={id:'media-'+entityId,file_url:'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5wAAAABJRU5ErkJggg==',file_name:'unit.png'};db.media[entityId]=[m];return m;}};
    window.supabaseClient={from(table){let payload,operation,id;const chain={select(){return chain;},eq(k,v){if(k==='id')id=v;return chain;},insert(p){payload=p;operation='insert';return chain;},update(p){payload=p;operation='update';return chain;},
      async order(){return{error:null,data:db.masters.map(p=>({...p,frames:db.frames.filter(f=>f.print_id===p.id)}))};},
      async in(k,vals){return{error:null,data:db.frames.filter(f=>vals.includes(f.frame_no))};},
      async single(){db.writes.push({operation,payload});let row;if(operation==='insert'){row={...payload,id:'print-'+(db.masters.length+1)};db.masters.push(row);}else{row=db.masters.find(p=>p.id===id);Object.assign(row,payload);}return{data:{...row},error:null};}};return chain;},
      async rpc(name,args){db.rpcCalls.push({name,args});if(db.holdFrames)await new Promise(resolve=>db.release=resolve);if(db.failFrames){db.failFrames--;return{error:{message:'temporary frame failure'}};}db.frames=db.frames.filter(f=>f.print_id!==args.p_print_id).concat(args.p_rows.map(f=>({...f,print_id:args.p_print_id})));return{error:null};}};
  });
  await p.addScriptTag({content:read('real-print-master.js')});
  await p.waitForSelector('.print-frame-row');
  return p;
}
async function fillPrint(p){
  await p.locator('#printNo').fill('UNIT-PRINT');await p.locator('#printName').fill('Regression Print');await p.locator('#designColours').fill('2');
  await p.locator('#galleryFiles').setInputFiles({name:'unit.png',mimeType:'image/png',buffer:Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5wAAAABJRU5ErkJggg==','base64')});
  for(let i=1;i<4;i++)await p.locator('#addFrameBtn').click();
  for(let i=0;i<4;i++)await p.locator('.frame-no').nth(i).fill('F'+(i+1));
}
async function chatPage(){
  const p=await pageFor('test70-cb-purchase-real-chat-pilot.html');
  const boot='document.readyState==="loading"?document.addEventListener("DOMContentLoaded",boot,{once:true}):boot();';
  const source=read('test70-real-chat-live-v70.js');assert.equal(source.split(boot).length,2);
  await p.addScriptTag({content:source.replace(boot,`window.__rc={S,inbox,openDepartment,openChat,load,saveCache,hydrateCache,cacheKey,departmentGroupVisibleCountsV730,setCountProjection:fn=>departmentVisibleProjectionV763=fn,setAlerts:fn=>adminPurchaseAlertsV692=fn};`)});
  await p.evaluate(()=>{
    const s=__rc.S;Object.assign(s,{userId:'browser-unit',actor:{id:'owner-unit',role:'SUPER_ADMIN'},status:'OPEN',userStatusLock:'OPEN',search:'',cards:[],cbCards:[],history:[],people:[],departments:['PRINTING','CUTTING','PURCHASE','ADMIN'].map(id=>({department_code:id,department_name:id,workers:[],staff:[]}))});
    __rc.setCountProjection(async()=>({OPEN:0,WORKING:0}));s.db={rpc:async()=>({error:null,data:{cards:[]}})};
  });
  return p;
}
(async()=>{
 browser=await chromium.launch({headless:true,...(process.env.TEST71_CHROMIUM_PATH?{executablePath:process.env.TEST71_CHROMIUM_PATH}:{})});
 try{
  await run('Print: two colours + four frames save and reopen unchanged',async()=>{
   const p=await printPage();await fillPrint(p);await p.locator('#savePrintBtn').click();await p.waitForSelector('[data-edit]');await p.locator('[data-edit]').click();
   assert.equal(await p.locator('#designColours').inputValue(),'2');assert.equal(await p.locator('.frame-no').count(),4);
   assert.deepEqual(await p.locator('.frame-no').evaluateAll(ns=>ns.map(n=>n.value)),['F1','F2','F3','F4']);
   assert.equal(await p.evaluate(()=>__printDb.masters.length),1);assert.equal(await p.evaluate(()=>__printDb.rpcCalls[0].args.p_allow_reassign),false);
   if(process.env.TEST71_EVIDENCE_DIR){fs.mkdirSync(process.env.TEST71_EVIDENCE_DIR,{recursive:true});await p.screenshot({path:path.join(process.env.TEST71_EVIDENCE_DIR,'print-two-colours-four-frames.png'),fullPage:true});}await p.close();
  });
  await run('Print: duplicate Frame Nos stay blocked without a master write',async()=>{
   const p=await printPage();await fillPrint(p);await p.locator('.frame-no').nth(3).fill('f1');await p.locator('#savePrintBtn').click();
   await p.waitForFunction(()=>document.getElementById('printMessage').textContent.includes('Duplicate Frame No'));
   assert.equal(await p.evaluate(()=>__printDb.writes.length),0);assert.equal(await p.locator('#savePrintBtn').isEnabled(),true);await p.close();
  });
  await run('Print: double submit is single-flight and a failed frame save retries the same master',async()=>{
   const p=await printPage();await fillPrint(p);await p.evaluate(()=>{__printDb.holdFrames=true;__printDb.failFrames=1;const f=document.getElementById('printForm');f.dispatchEvent(new Event('submit',{cancelable:true}));f.dispatchEvent(new Event('submit',{cancelable:true}));});
   await p.waitForFunction(()=>!!__printDb.release);assert.equal(await p.evaluate(()=>__printDb.writes.length),1);
   await p.evaluate(()=>{__printDb.holdFrames=false;__printDb.release();});await p.waitForFunction(()=>document.getElementById('printMessage').textContent.includes('temporary frame failure'));
   assert.equal(await p.locator('#printId').inputValue(),'print-1');await p.locator('#savePrintBtn').click();await p.waitForSelector('[data-edit]');
   assert.deepEqual(await p.evaluate(()=>__printDb.writes.map(w=>w.operation)),['insert','update']);assert.equal(await p.evaluate(()=>__printDb.masters.length),1);await p.close();
  });
  await run('Counts: a fast department paints before a slow one and retains its timestamp',async()=>{
   const p=await chatPage();await p.evaluate(()=>{window.calls={};__rc.setCountProjection(dep=>{calls[dep]=(calls[dep]||0)+1;return dep==='CUTTING'?new Promise(resolve=>window.finishSlow=resolve):Promise.resolve({OPEN:2,WORKING:4});});__rc.inbox();});
   await p.waitForFunction(()=>document.querySelector('[data-dept-count="PRINTING"]').textContent==='2 open · 4 working cards');
   assert.match(await p.locator('[data-dept-count="CUTTING"]').textContent(),/loading/);
   await p.evaluate(()=>finishSlow({OPEN:1,WORKING:3}));await p.waitForFunction(()=>document.querySelector('[data-dept-count="CUTTING"]').textContent==='1 open · 3 working cards');
   const at=await p.evaluate(()=>__rc.S.departmentCountCache.get('PRINTING').at);assert.ok(at>0);
   await p.evaluate(()=>__rc.inbox());assert.equal(await p.evaluate(()=>calls.PRINTING),1);assert.equal(await p.evaluate(()=>__rc.S.departmentCountCache.get('PRINTING').at),at);await p.close();
  });
  await run('Counts: failure never turns unknown into a confirmed zero; confirmed cache survives failure',async()=>{
   const p=await chatPage();await p.evaluate(()=>{__rc.setCountProjection(async()=>{throw Error('unit timeout');});__rc.S.departmentCountCache.set('PRINTING',{OPEN:7,WORKING:8,at:1});__rc.inbox();});
   await p.waitForFunction(()=>__rc.S.departmentCountJobs.size===0);
   assert.equal(await p.locator('[data-dept-count="PRINTING"]').textContent(),'7 open · 8 working cards');assert.match(await p.locator('[data-dept-count="CUTTING"]').textContent(),/loading/);
   assert.equal(await p.evaluate(()=>__rc.S.departmentCountCache.has('CUTTING')),false);await p.close();
  });
  await run('Counts: actor-scoped persisted cache restores without overwriting another identity',async()=>{
   const p=await chatPage();const value=await p.evaluate(()=>{__rc.S.departmentCountCache.set('PRINTING',{OPEN:3,WORKING:6,at:Date.now()});__rc.saveCache();__rc.S.departmentCountCache.clear();__rc.hydrateCache();const restored=__rc.S.departmentCountCache.get('PRINTING');window.RR_ON_BEHALF_ACTIVE=true;window.RR_VIEW_AS_ACTOR_ID='another-user';return{restored,other:sessionStorage.getItem(__rc.cacheKey())};});
   assert.equal(value.restored.OPEN,3);assert.equal(value.other,null);await p.close();
  });
  await run('CB group tap paints its shell before I/O and sends only one canonical request',async()=>{
   const p=await chatPage();await p.evaluate(()=>{window.rpcCalls=[];__rc.S.db.rpc=(name,args)=>{rpcCalls.push({name,args});return new Promise(resolve=>window.finishCb=resolve);};window.chatJob=__rc.openChat('group','PURCHASE',false);});
   assert.equal(await p.locator('#chatName').textContent(),'CB Department Group');assert.equal(await p.locator('#chat').isVisible(),true);assert.equal(await p.evaluate(()=>rpcCalls.filter(c=>c.name==='rr_cb_department_cards_v600').length),1);
   await p.evaluate(async()=>{finishCb({data:{cards:[]},error:null});await chatJob;});assert.equal(await p.locator('#chatName').textContent(),'CB Department Group');await p.close();
  });
  await run('Late CB response cannot change a newer department or cached CB cards',async()=>{
   const p=await chatPage();await p.evaluate(()=>{__rc.S.db.rpc=()=>new Promise(resolve=>window.finishCb=resolve);window.chatJob=__rc.openChat('group','PURCHASE',false);});
   await p.evaluate(()=>__rc.openDepartment('CUTTING',false));await p.evaluate(async()=>{finishCb({data:{cards:[{cb_no:'LATE'}]},error:null});await chatJob;});
   assert.equal(await p.locator('#chatName').textContent(),'CUTTING Department');assert.equal(await p.evaluate(()=>__rc.S.cbCards.length),0);await p.close();
  });
  await run('Late Admin alerts cannot repaint after back navigation',async()=>{
   const p=await chatPage();await p.evaluate(()=>{__rc.setAlerts(()=>new Promise(resolve=>window.finishAlerts=resolve));window.chatJob=__rc.openChat('group','ADMIN',false);});
   await p.waitForFunction(()=>!!window.finishAlerts);await p.evaluate(()=>__rc.openDepartment('PRINTING',false));await p.evaluate(async()=>{finishAlerts('<div id="stale-alert">STALE</div>');await chatJob;});
   assert.equal(await p.locator('#stale-alert').count(),0);assert.equal(await p.locator('#chatName').textContent(),'PRINTING Department');await p.close();
  });
  console.log('BROWSER REGRESSION PASS: '+results.length+'/'+results.length+' (isolated mocked I/O; no live DB mutation)');
 }finally{await browser.close();if(process.env.TEST71_EVIDENCE_DIR){fs.mkdirSync(process.env.TEST71_EVIDENCE_DIR,{recursive:true});fs.writeFileSync(path.join(process.env.TEST71_EVIDENCE_DIR,'browser-results.json'),JSON.stringify(results,null,2));}}
})().catch(e=>{console.error(e);process.exitCode=1;});
