const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {JSDOM}=require('jsdom');
function fixture(){
 const dom=new JSDOM('<section id="inbox"><header class="head"><h1>Chat</h1></header><button data-department="STICKER"><b>Sticker</b></button></section><section id="chat"><div id="messages"><article data-assignment-id="a"><h2>Lot 2633</h2></article></div></section>',{url:'https://test71-workspace.app.github.dev/test70-cb-purchase-real-chat-pilot.html',runScripts:'outside-only',pretendToBeVisual:true});
 const w=dom.window;w.setInterval=w.setTimeout=()=>0;let hiddenSecond=true;const reads=[];const recipients=[{worker_name:'Kartik',role_code:'WORKER',delivered_at:'2026-10-08T03:00:00Z',read_at:null},{worker_name:'Manager',role_code:'MANAGER',delivered_at:null,read_at:null}];
 const rows=['Assign','Accept & Count'].map((action_label,i)=>({id:'n'+i,action_key:'action'+i,action_label,assignment_id:'a',department_code:'STICKER',route_url:'?rc_status=WORKING',worker_ids:['kartik'],created_at:'2026-10-08T02:00:00Z',actor_name:'Lineman',recipients:JSON.parse(JSON.stringify(recipients))}));let notices=rows.slice();
 w.RRAdminApprovalHost71={context:()=>({kind:'group',id:'STICKER',status:'WORKING'})};w.RF853={rpc:async(n,a)=>{
 if(n==='rr_chat_notification_inbox_test71')return notices;if(n==='rr_chat_staff_unread_test71')return [];
 if(n==='rr_chat_action_history_test71')return rows;if(n==='rr_chat_action_delivered_test71')return notices.length;
 if(n==='rr_chat_action_receipts_test71')return recipients;
 if(n==='rr_chat_notification_read_test71'){reads.push(...a.p_ids);notices=notices.filter(r=>!a.p_ids.includes(r.id));return a.p_ids.length;}throw Error(n);
 }};
 w.document.getElementById('chat').getBoundingClientRect=()=>({top:0,bottom:600,height:600,width:300});
 w.HTMLElement.prototype.getBoundingClientRect=function(){const off=this.dataset.actionKey==='action1'&&hiddenSecond;return {top:off?900:100,bottom:off?1000:180,height:80,width:300};};w.HTMLElement.prototype.scrollIntoView=function(){};
 w.HTMLDialogElement.prototype.showModal=function(){this.open=true;};w.HTMLDialogElement.prototype.close=function(){this.open=false;};
 w.eval(fs.readFileSync('real-chat-inbox-summary-test71.js','utf8'));w.eval(fs.readFileSync('real-chat-action-receipts-test71.js','utf8'));
 return{w,dom,reads,rows,showSecond:()=>hiddenSecond=false};
}
test('two actions on one card: only visible action reads; popup keeps the other recipient unread',async()=>{const f=fixture(),{w}=f;try{
 await w.RRChatNotifications71.refresh();assert.deepEqual(f.reads,['n0']);assert.equal(w.document.querySelectorAll('[data-action-key]').length,2);assert.equal(w.document.querySelector('[data-unread-bubble="total"]').textContent,'Unread 1');assert.equal(w.document.querySelector('[data-action-key="action1"] .rrActionNew71').textContent,'Unread');
 await w.RRActionReceipts71.details('action0');assert.match(w.document.querySelector('dialog').textContent,/Kartik/);assert.match(w.document.querySelector('dialog').textContent,/Manager/);assert.match(w.document.querySelector('dialog').textContent,/Sent/);assert.deepEqual(f.reads,['n0']);
 f.showSecond();await w.RRChatNotifications71.visible();assert.deepEqual(f.reads,['n0']);w.document.querySelector('dialog').close();await w.RRChatNotifications71.visible();assert.deepEqual(f.reads,['n0','n1']);assert.equal(w.document.querySelector('[data-unread-bubble="total"]'),null);
 }finally{f.dom.window.close();}});
test('own read turns blue; all participants read turns green; other recipients read does not turn blue',()=>{const f=fixture();try{const state=f.w.RRActionReceipts71.state;assert.equal(state([{read_at:'today'},{delivered_at:'today'}]).blue,false);assert.equal(state([{read_at:'today'},{read_at:'today'}],true).green,true);assert.equal(state([{read_at:'today'},{read_at:'today'}],true).blue,false);assert.equal(state([{read_at:'today'},{delivered_at:'today'}],true).blue,true);assert.equal(state([{delivered_at:'today'}]).label,'Delivered');assert.equal(state([]).blue,false);}finally{f.dom.window.close();}});
test('read RPC failure keeps NEW and bubble; no optimistic acknowledgement',async()=>{const f=fixture();try{const old=f.w.RF853.rpc;f.w.RF853.rpc=async(n,a)=>n==='rr_chat_notification_read_test71'?0:old(n,a);await f.w.RRChatNotifications71.refresh();assert.equal(f.w.document.querySelector('[data-unread-bubble="total"]').textContent,'Unread 2');assert.equal(f.w.document.querySelectorAll('.rrActionNew71').length,2);}finally{f.dom.window.close();}});

test('late inbox response cannot restore an action read while polling was pending',async()=>{const f=fixture();try{
 await f.w.RRChatNotifications71.refresh();const old=f.w.RF853.rpc;let release;f.w.RF853.rpc=(n,a)=>n==='rr_chat_notification_inbox_test71'?new Promise(resolve=>release=resolve):old(n,a);
 const polling=f.w.RRChatNotifications71.refresh();f.showSecond();await f.w.RRChatNotifications71.visible();release(f.rows.slice());await polling;
 assert.equal(f.w.document.querySelector('[data-unread-bubble="total"]'),null);assert.deepEqual(f.reads,['n0','n1']);
 }finally{f.dom.window.close();}});

test('another device already read: zero update reconciles own count from server',async()=>{const f=fixture();try{
 const old=f.w.RF853.rpc;let read=false;f.w.RF853.rpc=async(n,a)=>{if(n==='rr_chat_notification_read_test71'){read=true;return 0;}if(n==='rr_chat_notification_inbox_test71'&&read)return [];return old(n,a);};
 await f.w.RRChatNotifications71.refresh();assert.equal(f.w.document.querySelector('[data-unread-bubble="total"]'),null);
 }finally{f.dom.window.close();}});

test('other status actions stay on their own tab without detached text sections or read acknowledgement',async()=>{const f=fixture();try{
 f.rows[0].route_url='?rc_status=CLOSE';await f.w.RRChatNotifications71.refresh();assert.equal(f.w.RRActionReceipts71.entry(f.rows[0]),null);assert.equal(f.w.document.querySelector('[data-unmapped-actions]'),null);assert.deepEqual(f.reads,[]);assert.equal(f.w.document.querySelector('[data-unread-bubble="total"]').textContent,'Unread 2');
 }finally{f.dom.window.close();}});
test('unmapped targeted action is never attached to a same-lot sibling or marked read',async()=>{const f=fixture();try{
 f.rows[0].assignment_id='other-assignment';await f.w.RRChatNotifications71.refresh();assert.equal(f.w.RRActionReceipts71.entry(f.rows[0]),null);assert.equal(f.w.document.querySelector('[data-unmapped-actions]'),null);assert.deepEqual(f.reads,[]);
 }finally{f.dom.window.close();}});
test('card tick is blue for viewer read and green after every participant reads',async()=>{const f=fixture();try{
 const old=f.w.RF853.rpc;f.rows[0].viewer_is_recipient=true;f.rows[0].viewer_read_at='2026-10-09T05:00:00Z';f.w.RF853.rpc=async(n,a)=>n==='rr_chat_notification_inbox_test71'?[f.rows[1]]:old(n,a);
 await f.w.RRChatNotifications71.refresh();let tick=f.w.RRActionReceipts71.entry(f.rows[0]).querySelector('[data-action-receipt]');assert.ok(tick.classList.contains('read'));assert.ok(!tick.classList.contains('all-read'));
 f.rows[0].recipients.forEach(r=>r.read_at='2026-10-09T05:00:00Z');f.w.RRActionReceipts71.render();tick=f.w.RRActionReceipts71.entry(f.rows[0]).querySelector('[data-action-receipt]');assert.ok(tick.classList.contains('all-read'));assert.ok(!tick.classList.contains('read'));assert.match(tick.textContent,/All read/);
 }finally{f.dom.window.close();}});
test('card keeps own blue then all-read green alongside a shared named red actor tick; popup has one tick per person',async()=>{const f=fixture();try{
 const old=f.w.RF853.rpc;f.w.RRAdminApprovalHost71.context=()=>({kind:'group',id:'STICKER',status:'WORKING',userId:'ali-id'});f.rows[0].viewer_read_at='2026-10-09T05:00:00Z';f.rows[0].actor_user_id='other-id';f.w.RF853.rpc=async(n,a)=>n==='rr_chat_notification_inbox_test71'?[f.rows[1]]:old(n,a);await f.w.RRChatNotifications71.refresh();let entry=f.w.RRActionReceipts71.entry(f.rows[0]);assert.equal(entry.querySelectorAll('[data-action-receipt]').length,1);assert.ok(entry.querySelector('[data-action-receipt]').classList.contains('read'));
 f.rows[0].actor_user_id='ali-id';f.rows[0].actor_name='Ali';f.w.RRActionReceipts71.render();entry=f.w.RRActionReceipts71.entry(f.rows[0]);assert.equal(entry.querySelectorAll('[data-action-receipt]').length,1);assert.ok(entry.querySelector('[data-action-receipt]').classList.contains('read'));assert.equal(entry.querySelectorAll('.rrActorTick71').length,1);assert.match(entry.querySelector('.rrCardActor71').textContent,/Ali/);assert.equal(entry.querySelector('.rrActionOwnState71'),null);
 f.rows[0].recipients.forEach(r=>r.read_at='2026-10-09T05:00:00Z');f.w.RRActionReceipts71.render();assert.ok(entry.querySelector('[data-action-receipt]').classList.contains('all-read'));assert.equal(entry.querySelectorAll('.rrActorTick71').length,1);
 await f.w.RRActionReceipts71.details('action0');const list=f.w.document.querySelectorAll('.rrParticipants71 li');assert.equal(list.length,3);for(const person of list)assert.equal(person.querySelectorAll('.rrParticipantTick71').length,1);assert.equal(f.w.document.querySelectorAll('.rrParticipantTick71.action-taken').length,1);assert.match(f.w.document.querySelector('.rrParticipantTick71.action-taken').textContent,/✓✓ Action taken/);
 }finally{f.dom.window.close();}});
test('participant popup uses single grey sent, double grey delivered, double blue read, double red actor',()=>{const f=fixture();try{const state=f.w.RRActionReceipts71.participantState;assert.equal(state({},{}).ticks,'✓');assert.equal(state({},{}).label,'Sent');assert.equal(state({delivered_at:'today'},{}).ticks,'✓✓');assert.equal(state({delivered_at:'today'},{}).className,'delivered');assert.equal(state({read_at:'today'},{}).className,'read');assert.equal(state({recipient_id:'ali',read_at:'today'},{actor_user_id:'ali'}).className,'action-taken');}finally{f.dom.window.close();}});
test('source card without action history gets one persistent own blue tick and participant popup',async()=>{const f=fixture();try{
 const row={card_receipt:true,action_key:'source-a',assignment_id:'a',lot_no:'2640',department_code:'STICKER',route_url:'?rc_status=WORKING',action_label:'Card',recipients:[{recipient_id:'me',worker_name:'Me',read_at:null},{recipient_id:'other',worker_name:'Other',read_at:null}]};let readCalls=0;const old=f.w.RF853.rpc;f.w.RRAdminApprovalHost71.context=()=>({kind:'group',id:'STICKER',status:'WORKING',userId:'me'});f.w.RF853.rpc=async(n,a)=>{if(n==='rr_chat_action_history_test71'||n==='rr_chat_notification_inbox_test71')return [];if(n==='rr_chat_source_card_receipts_test71'){if(a.p_read_keys.includes(row.action_key)){readCalls++;row.viewer_read_at='today';row.recipients[0].read_at='today';}return [JSON.parse(JSON.stringify(row))];}return old(n,a);};
 await f.w.RRChatNotifications71.refresh();let tick=f.w.document.querySelector('[data-action-receipt]');assert.equal(f.w.document.querySelectorAll('[data-action-receipt]').length,1);assert.ok(tick.classList.contains('read'));assert.equal(row.recipients[1].read_at,null);assert.equal(readCalls,1);await f.w.RRActionReceipts71.refresh();assert.equal(readCalls,1);await f.w.RRActionReceipts71.details(row.action_key);assert.equal(f.w.document.querySelectorAll('.rrParticipants71 li').length,2);f.w.document.querySelector('dialog').close();row.recipients[1].read_at='today';await f.w.RRActionReceipts71.refresh();tick=f.w.document.querySelector('[data-action-receipt]');assert.ok(tick.classList.contains('all-read'));row.actor_user_id='me';await f.w.RRActionReceipts71.refresh();assert.ok(f.w.document.querySelector('[data-action-receipt]').classList.contains('all-read'));assert.equal(f.w.document.querySelectorAll('.rrActorTick71').length,1);
 }finally{f.dom.window.close();}});


test('footer uses two clear lines: named action with red ticks, then Read with blue or All read with green',async()=>{const f=fixture();try{
 const old=f.w.RF853.rpc;f.w.RRAdminApprovalHost71.context=()=>({kind:'group',id:'STICKER',status:'WORKING',userId:'viewer'});
 Object.assign(f.rows[0],{actor_user_id:'imamul',actor_name:'Imamul',actor_action_label:'SUBMIT',viewer_read_at:'today'});
 f.w.RF853.rpc=async(n,a)=>n==='rr_chat_notification_inbox_test71'?[f.rows[1]]:old(n,a);
 await f.w.RRChatNotifications71.refresh();const entry=f.w.RRActionReceipts71.entry(f.rows[0]);
 assert.equal(entry.children.length,2);assert.ok(entry.children[0].classList.contains('rrCardActor71'));assert.match(entry.children[0].textContent,/Imamul · Submitted.*✓✓/);
 assert.ok(entry.children[1].classList.contains('read'));assert.match(entry.children[1].textContent,/Read.*✓✓/);assert.equal(entry.querySelectorAll('strong').length,0);
 f.rows[0].recipients.forEach(r=>r.read_at='today');f.w.RRActionReceipts71.render();assert.ok(entry.children[1].classList.contains('all-read'));assert.match(entry.children[1].textContent,/All read.*✓✓/);assert.equal(entry.querySelectorAll('.rrActorTick71').length,1);
 }finally{f.dom.window.close();}});
test('all action descriptions use consistent plain verbs; incomplete acceptance never says completed',()=>{const f=fixture();try{const describe=f.w.RRActionReceipts71.actionDescription;
 for(const [value,expected] of [['SUBMIT','Submitted'],['ASSIGN_WORKER','Assigned'],['ACCEPT & COUNT','Accept & Count completed'],['HANDOVER_COMPLETED','Accept & Count completed'],['Submit · Accept & Count pending','Accept & Count pending'],['LM_ACCEPTED','Accept & Count started'],['ALTER','Altered'],['ALTER_SUBMIT','Alter submitted'],['RECTIFICATION_CLOSE','Rectified'],['RECTIFICATION','Rectify started'],['LOGIN_APPROVED','Approved'],['PI_SHARED','Shared'],['CARD_UPDATED','Updated']])assert.equal(describe(value),expected);
 }finally{f.dom.window.close();}});

test('worker Working card shows completed Accept & Count, yellow Submit pending, then blue Read',async()=>{const f=fixture();try{
 const card=f.w.document.querySelector('article');card.insertAdjacentHTML('beforeend','<div class="card-actions"><button data-chat-submit="a">SUBMIT</button><button data-chat-alter>ALTER</button><button data-chat-rectify>RECTIFY</button></div>');
 Object.assign(f.rows[0],{actor_user_id:'sudesh',actor_name:'Sudesh Bhati',actor_action_label:'CONFIRM_RECEIVED_PCS',viewer_read_at:'today'});
 await f.w.RRChatNotifications71.refresh();const entry=f.w.RRActionReceipts71.entry(f.rows[0]);assert.match(entry.children[0].textContent,/पिछला action: Sudesh Bhati · Accept & Count completed/);
 assert.equal(entry.children[1].textContent,'अगला action बाकी: SUBMIT');assert.ok(entry.children[2].classList.contains('read'));assert.equal(card.querySelectorAll('.rrCardPending71').length,1);
 const pendingLine=card.querySelector('.rrCardPending71'),readLine=entry.children[2];f.w.RRActionReceipts71.render();assert.equal(card.querySelectorAll('.rrCardPending71').length,1);assert.equal(card.querySelector('.rrCardPending71'),pendingLine);assert.equal(entry.children[2],readLine);assert.equal(card.querySelectorAll('.card-actions button').length,3);
 card.querySelector('.card-actions').remove();f.w.RRActionReceipts71.render();assert.equal(card.querySelector('.rrCardPending71'),null);
 }finally{f.dom.window.close();}});
test('pending description follows the actual available action for each workflow',()=>{const f=fixture();try{
 const card=f.w.document.querySelector('article'),pending=f.w.RRActionReceipts71.pendingAction;
 for(const [attr,label,expected] of [['data-fab-receive','ACCEPT & COUNT','ACCEPT & COUNT'],['data-receipt-accept','ACCEPT & COUNT','ACCEPT & COUNT'],['data-assign-action','ASSIGN WORK','ASSIGN WORKER'],['data-rate-popup','FILL ACTUAL RATE','FILL ACTUAL RATE'],['data-alter-action','RECEIVE FROM MASTER','RECEIVE FROM MASTER'],['data-action','RECTIFY FINAL CLOSE','RECTIFY FINAL CLOSE']]){card.innerHTML='<div class="card-actions"><button '+attr+'> '+label+' </button></div>';assert.equal(pending(card),expected);}
 card.innerHTML='<div class="card-actions"><button disabled>SUBMIT</button></div>';assert.equal(pending(card),'');
 f.w.RRAdminApprovalHost71.context=()=>({status:'CLOSE'});card.innerHTML='<div class="card-actions"><button data-chat-submit>SUBMIT</button></div>';assert.equal(pending(card),'');
 }finally{f.dom.window.close();}});
