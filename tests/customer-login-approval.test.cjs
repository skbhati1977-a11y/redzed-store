const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const src=name=>fs.readFileSync((fs.existsSync('dist/'+name)?'dist/':'')+name,'utf8');
function fixture(rpc){
 const values=new Map(),modalMessages=[],clients=[],appended=[];
 const localStorage={getItem:k=>values.get(k)||null,setItem:(k,v)=>values.set(k,v),removeItem:k=>values.delete(k)};
 const document={readyState:'loading',addEventListener(){},getElementById:()=>null,createElement:()=>{
  const message={textContent:'',style:{},setAttribute(){}};modalMessages.push(message);
  return {style:{},querySelector:sel=>sel==='[data-wait]'?message:null,querySelectorAll:()=>[],remove(){this.removed=true;}};
 },body:{appendChild:n=>appended.push(n)}};
 const window={supabase:{createClient:(url,key,options)=>{clients.push(options);return {rpc};}}};
 const context={window,document,location:{search:'?t=original-share'},URLSearchParams,localStorage,RF853:{rpc},SUPABASE_URL:'https://example.invalid',SUPABASE_ANON_KEY:'public-key',setTimeout:resolve=>queueMicrotask(resolve),CustomEvent:function(){},crypto:require('node:crypto').webcrypto,Uint8Array,console};
 const s=src('real-customer-secure-session-addon-v9592.js').replace('  const invalidSession =','  window.test={issue,restore,waitForApproval,device};\n  const invalidSession =');
 vm.runInNewContext(s,context);return {context,values,clients,appended,modalMessages,test:window.test};
}

test('pending approval cannot store a session; approval binds transport to that device',async()=>{
 let issueCount=0,approve;
 const calls=[];const f=fixture(async(name,args)=>{
  calls.push([name,args]);
  if(name==='rr_customer_session_issue_bound_v9680')return ++issueCount===1?{approval_status:'PENDING',request_id:'req-1',customer_name:'Customer'}:{approval_status:'APPROVED',session_token:'server-session',customer_name:'Customer'};
  if(name==='rr_customer_login_status_test71')return new Promise(resolve=>approve=()=>resolve({approval_status:'APPROVED'}));
  if(name==='rr_customer_session_validate_v9590')return {valid:true,customer_id:'customer',data_mode:'TEST'};
 });
 f.values.set('rr_customer_device_v9592','this-device');
 const result=f.test.issue({name:'Customer',mobile:'9000000000'},'this-device');
 await new Promise(resolve=>setImmediate(resolve));
 assert.equal(f.values.has('rr_customer_secure_session_v9592'),false);assert.equal(f.clients.length,0);
 assert.match(f.modalMessages[0].textContent,/approval का इंतज़ार/);
 approve();await result;
 assert.equal(JSON.parse(f.values.get('rr_customer_secure_session_v9592')).session_token,'server-session');
 assert.equal(f.clients[0].global.headers['x-rr-customer-session'],'server-session');
 assert.equal(f.clients[0].global.headers['x-rr-customer-device'],'this-device');
 assert.equal(f.clients[0].auth.persistSession,false);
 assert(!calls.some(([name])=>name.includes('approval_decide')));
});

test('rejected device stays logged out',async()=>{
 const f=fixture(async name=>name==='rr_customer_session_issue_bound_v9680'?{approval_status:'REJECTED',request_id:'req-1'}:{});
 await assert.rejects(f.test.issue({name:'Customer',mobile:'9000000000'},'this-device'),/approval rejected/);
 assert.equal(f.clients.length,0);assert.equal(f.values.has('rr_customer_secure_session_v9592'),false);assert(f.appended[0].removed);
});

test('old unapproved sessions are cleared before requesting new approval',async()=>{
 let validationCount=0,issueCount=0,approve;
 const f=fixture(async name=>{
  if(name==='rr_customer_session_validate_v9590'){if(++validationCount===1)throw Error('Super Admin approval required for this device.');return {valid:true,customer_id:'customer',data_mode:'TEST'};}
  if(name==='rr_customer_session_issue_bound_v9680')return ++issueCount===1?{approval_status:'PENDING',request_id:'req-2'}:{session_token:'approved-session',customer_name:'Customer'};
  if(name==='rr_customer_login_status_test71')return new Promise(resolve=>approve=()=>resolve({approval_status:'APPROVED'}));
 });
 f.values.set('rr_customer_device_v9592','this-device');
 f.values.set('rr_customer_secure_session_v9592',JSON.stringify({share_token:'original-share',session_token:'legacy-session'}));
 f.values.set('rr_customer_device_login_test71',JSON.stringify({name:'Customer',mobile:'9000000000'}));
 const promise=f.test.restore();await new Promise(resolve=>setImmediate(resolve));
 assert.equal(f.values.has('rr_customer_secure_session_v9592'),false);approve();await promise;
 assert.equal(JSON.parse(f.values.get('rr_customer_secure_session_v9592')).session_token,'approved-session');
});

test('customer loaders wait for approval before loading collection and chat modules',()=>{
 for(const file of ['s.html',...(fs.existsSync('dist/index.html')?['index.html']:[])]){
  const s=src(file);assert.match(s,/src\.startsWith\('real-customer-secure-session-addon-v9592\.js'\)\) await window\.RR_CUSTOMER_SECURE_SESSION_V9592\.ensure\(\)/);
 }
});

test('refresh draft cannot copy quantities from Collection 16 into Collection 12',()=>{
 const s=src('real-customer-chat-collection-card-v9605.js'),start=s.indexOf('function restorePullDraft()'),end=s.indexOf('async function openReadOnly',start);
 const input={value:'36',dataset:{}},note={value:''},panel={dataset:{collectionCycleId:'cycle-12'}};
 let draft={url:'/s.html?t=old',collectionCycleId:'cycle-16',quantities:[['1RR1','58']],note:'old note'};
 const ctx={location:{pathname:'/s.html',search:'?t=old'},sessionStorage:{getItem:()=>JSON.stringify(draft),removeItem(){}},document:{querySelector:()=>input},$:id=>({fcPanel:panel,fcNote:note})[id],CSS:{escape:x=>x},clampQuantity(){}};
 vm.runInNewContext(s.slice(start,end),ctx);ctx.restorePullDraft();assert.equal(input.value,'36');assert.equal(note.value,'');
 draft.collectionCycleId='cycle-12';ctx.restorePullDraft();assert.equal(input.value,'58');assert.equal(note.value,'old note');assert.equal(input.dataset.rrPullDraft71,'1');
});

test('Super Admin approval queue does not appear for an unauthorized account',async()=>{
 let boot,created=0;
 const context={location:{pathname:'/real-sales-live-chat-v9434.html',search:''},URLSearchParams,window:{RF853:{rpc:async()=>{throw Error('Super Admin ID required.');}}},RF853:{rpc:async()=>{throw Error('Super Admin ID required.');}},document:{readyState:'loading',addEventListener:(name,fn)=>{if(name==='DOMContentLoaded')boot=fn;},createElement:()=>{created++;return{};}},setTimeout(){},setInterval(){throw Error('Unauthorized polling started');}};
 vm.runInNewContext(src('real-customer-login-approvals-test71.js'),context);await boot();assert.equal(created,0);
});
