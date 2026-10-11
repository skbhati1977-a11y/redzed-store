const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),{JSDOM}=require('jsdom');
const source=fs.readFileSync('real-chat-inbox-summary-test71.js','utf8');
for(const personal of [false,true])test(`read notification focuses exact card in ${personal?'personal':'group'} chat`,async()=>{
 const d=new JSDOM('<div id="chat"><div id="messages"><article data-assignment-id="other"></article><details><article data-assignment-id="wanted"></article></details></div></div>',{url:'https://portal.test/chat?rc_notice=read-notice',runScripts:'outside-only',pretendToBeVisual:true}),w=d.window;
 try{
  w.setInterval=()=>0;w.setTimeout=()=>0;w.innerHeight=800;
  const n={id:'read-notice',assignment_id:'wanted',department_code:'CUTTING',worker_ids:['worker'],route_url:'/chat?rc_status=WORKING'};
  w.RF853={rpc:async()=>[]};w.RRAdminApprovalHost71={context:()=>({kind:personal?'person':'group',id:personal?'worker':'CUTTING',parentDepartment:'CUTTING',status:'WORKING'}),focusNotice:()=>false};
  w.RRActionReceipts71={notice:()=>n,render(){},visibleCards:async()=>{},entry:()=>null};
  let focused=0;const card=w.document.querySelector('[data-assignment-id="wanted"]');card.scrollIntoView=()=>focused++;
  w.eval(source);await w.RRChatNotifications71.visible();
  assert.equal(focused,1);assert.equal(card.parentElement.open,true);assert.equal(w.document.activeElement,card);assert(!w.document.querySelector('[data-assignment-id="other"]').classList.contains('rrNoticeFocus71'));
  await w.RRChatNotifications71.visible();assert.equal(focused,1);

 }finally{w.close()}
});

test('read notice from another worker does not focus a same-department card',async()=>{
 const d=new JSDOM('<div id="chat"><div id="messages"><article data-assignment-id="wanted"></article></div></div>',{url:'https://portal.test/chat?rc_notice=read-notice',runScripts:'outside-only',pretendToBeVisual:true}),w=d.window;
 try{w.setInterval=()=>0;w.setTimeout=()=>0;w.RF853={rpc:async()=>[]};w.RRAdminApprovalHost71={context:()=>({kind:'person',id:'different',parentDepartment:'CUTTING',status:'WORKING'}),focusNotice:()=>false};w.RRActionReceipts71={notice:()=>({id:'read-notice',assignment_id:'wanted',department_code:'CUTTING',worker_ids:['worker'],route_url:'/chat?rc_status=WORKING'}),render(){},visibleCards:async()=>{},entry:()=>null};let focused=0;w.document.querySelector('article').scrollIntoView=()=>focused++;w.eval(source);await w.RRChatNotifications71.visible();assert.equal(focused,0);}finally{w.close()}
});

test('missing assignment cannot focus another assignment sharing CB',()=>{
 const d=new JSDOM('<div id="messages"><article data-assignment-id="other" data-cb-no="CB-1"></article></div>',{url:'https://portal.test/chat',runScripts:'outside-only'}),w=d.window;
 try{w.setInterval=()=>0;w.setTimeout=()=>0;w.eval(source);assert.equal(w.RRChatNotifications71.target({assignment_id:'missing',cb_no:'CB-1',route_url:'/chat'}),null);}finally{w.close()}
});
test('consolidated event selects its exact card before shared CB fallback',()=>{
 const d=new JSDOM('<div id="messages"><article data-cb-no="CB-1"></article><article data-source-event-keys=\'["exact"]\' data-cb-no="CB-1"></article></div>',{url:'https://portal.test/chat',runScripts:'outside-only'}),w=d.window;
 try{w.setInterval=()=>0;w.setTimeout=()=>0;w.eval(source);assert.equal(w.RRChatNotifications71.target({event_key:'exact',cb_no:'CB-1',route_url:'/chat'}),w.document.querySelector('[data-source-event-keys]'));}finally{w.close()}
});
