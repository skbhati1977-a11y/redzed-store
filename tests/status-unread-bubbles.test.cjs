const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {JSDOM}=require('jsdom');
test('OPEN and WORKING badges scope to root, department and worker; reading one status leaves the other intact',async()=>{
 const dom=new JSDOM('<section id="inbox"><header class="head"><h1>Chat</h1></header><button data-status="OPEN">OPEN</button><button data-status="WORKING">WORKING</button></section><section id="chat"><button data-chat-status="OPEN">OPEN</button><button data-chat-status="WORKING">WORKING</button><div id="messages"><article data-event-key="open-a"><h2>A</h2></article><article data-event-key="working-a"><h2>A</h2></article></div></section>',{url:'https://example.test/',runScripts:'outside-only',pretendToBeVisual:true}),w=dom.window;
 let context={kind:'department',id:'PRINTING',status:'OPEN'},rows=[['o1','PRINTING','OPEN','a','open-a'],['o2','PRINTING','OPEN','b','open-b'],['w1','PRINTING','WORKING','a','working-a'],['w2','STICKER','WORKING','c','working-c']].map(([id,department_code,status,worker,event_key])=>({id,department_code,worker_ids:[worker],event_key,route_url:'?rc_status='+status}));
 w.setTimeout=w.setInterval=()=>0;w.RRAdminApprovalHost71={context:()=>context};w.RF853={rpc:async(name,args)=>{if(name==='rr_chat_notification_inbox_test71')return rows;if(name==='rr_chat_staff_unread_test71')return [];if(name==='rr_chat_notification_read_test71'){rows=rows.filter(n=>!args.p_ids.includes(n.id));return args.p_ids.length;}throw Error(name);}};
 w.document.getElementById('chat').getBoundingClientRect=()=>({top:0,bottom:600});w.HTMLElement.prototype.getBoundingClientRect=()=>({top:100,bottom:180,width:300,height:80});
 const count=(attribute,status)=>w.document.querySelector('['+attribute+'="'+status+'"] [data-unread-bubble="status"]')?.textContent;
 try{
  w.eval(fs.readFileSync('real-chat-inbox-summary-test71.js','utf8'));await w.RRChatNotifications71.refresh();
  assert.equal(count('data-status','OPEN'),'2');assert.equal(count('data-status','WORKING'),'2');assert.equal(count('data-chat-status','OPEN'),'2');assert.equal(count('data-chat-status','WORKING'),'1');
  context={kind:'person',id:'a',parentDepartment:'PRINTING',status:'OPEN'};w.RRChatNotifications71.paint();assert.equal(count('data-chat-status','OPEN'),'1');assert.equal(count('data-chat-status','WORKING'),'1');
  await w.RRChatNotifications71.visible();assert.equal(count('data-chat-status','OPEN'),undefined);assert.equal(count('data-chat-status','WORKING'),'1');assert.equal(count('data-status','OPEN'),'1');
  context.status='WORKING';await w.RRChatNotifications71.visible();assert.equal(count('data-chat-status','WORKING'),undefined);assert.equal(count('data-status','WORKING'),'1');
  context={kind:'department',id:'PRINTING',status:'WORKING'};w.RRChatNotifications71.paint();assert.equal(count('data-chat-status','OPEN'),'1');assert.equal(count('data-chat-status','WORKING'),undefined);
 }finally{w.close();}
});
