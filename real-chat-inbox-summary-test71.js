(()=>{'use strict';
 if(window.RRChatNotifications71)return;
 let notices=[],customers=[],busy=false,reading=false,focusDone=false,focusedNotice=null;
 const confirmedReads=new Set();
 const ready=()=>!!(window.RF853?.rpc||window.supabaseClient?.rpc);
 async function rpc(name,args={}){if(window.RF853?.rpc)return window.RF853.rpc(name,args);const db=window.supabaseClient;if(!db?.rpc)throw Error('Chat connection loading');const {data,error}=await db.rpc(name,args);if(error)throw error;return data;}
 const q=new URLSearchParams(location.search),noticeId=q.get('rc_notice'),bridgeId=q.get('rc_bridge');
 const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const style=document.createElement('style');style.textContent='.rrMsgBubble71{display:inline-flex;align-items:center;justify-content:center;min-width:25px;height:25px;padding:0 7px;margin-left:8px;border-radius:999px;background:#25a85a;color:white;font:800 13px system-ui;flex-shrink:0}.rrNoticeFocus71{outline:3px solid #ffe095!important;scroll-margin:24px}';document.head.appendChild(style);
 function bubble(host,n,key){if(!host)return;let b=host.querySelector('[data-unread-bubble="'+key+'"]');if(!n){b?.remove();return}if(!b){b=document.createElement('span');b.className='rrMsgBubble71';b.dataset.unreadBubble=key;host.appendChild(b)}const value='Unread '+String(n);if(b.textContent!==value)b.textContent=value;b.setAttribute('aria-label',value+' unread actions')}
 const belongs=(n,worker)=>Array.isArray(n.worker_ids)&&n.worker_ids.some(id=>id&&String(id)===String(worker));
 function paint(){
  if(focusedNotice){const node=target(focusedNotice);if(node)node.classList.add('rrNoticeFocus71')}

  const byDept=new Map();for(const n of notices)byDept.set(n.department_code,(byDept.get(n.department_code)||0)+1);
  const customerTotal=customers.reduce((n,x)=>n+Number(x.unread_count||0),0);
  // Customer conversations belong to the Sales customer-chat engine, not work-card counts.
  byDept.set('SALES',(byDept.get('SALES')||0)+customerTotal);
  const total=notices.length+customerTotal;bubble(document.querySelector('#inbox .head h1'),total,'total');try{const result=total?navigator.setAppBadge?.(total):navigator.clearAppBadge?.();result?.catch(()=>{});}catch(_){}
  document.querySelectorAll('[data-department],[data-dept-group]').forEach(row=>{const dep=String(row.dataset.department||row.dataset.deptGroup).toUpperCase();bubble(row.querySelector('b'),byDept.get(dep)||0,'department');const badge=row.querySelector('[data-unread-bubble="department"]');if(badge){badge.setAttribute('role','button');badge.tabIndex=0;const open=event=>{event.preventDefault();event.stopPropagation();const first=notices.find(n=>n.department_code===dep);if(first)location.href=first.route_url+(first.route_url.includes('?')?'&':'?')+'rc_notice='+encodeURIComponent(first.id);else if(dep==='SALES'&&customers.find(n=>Number(n.unread_count)>0))location.href='real-sales-live-chat-v9434.html?chat='+encodeURIComponent(customers.find(n=>Number(n.unread_count)>0).chat_id);};badge.onclick=open;badge.onkeydown=e=>{if(e.key==='Enter'||e.key===' ')open(e)};}});
  const context=window.RRAdminApprovalHost71?.context();
  // Status tabs count this identity's unread actions, independent of the selected tab.
  const scope=notices.filter(n=>!context?.id||!['department','group','person'].includes(context.kind)||
   n.department_code===String(context.parentDepartment||context.id).toUpperCase()&&(context.kind!=='person'||belongs(n,context.id)));
  document.querySelectorAll('[data-status],[data-chat-status]').forEach(button=>{
   const status=String(button.dataset.chatStatus||button.dataset.status).toUpperCase();
   const rows=button.closest('#inbox')?notices:scope;
   const count=rows.filter(n=>new URL(n.route_url,location.href).searchParams.get('rc_status')===status).length;
   bubble(button,count,'status');
  });
  document.querySelectorAll('[data-person]').forEach(row=>{const matches=notices.filter(n=>n.department_code===String(context?.parentDepartment||context?.id||'').toUpperCase()&&belongs(n,row.dataset.person));bubble(row.querySelector('b'),matches.length,'chat');const badge=row.querySelector('[data-unread-bubble="chat"]');if(badge){badge.setAttribute('role','button');badge.tabIndex=0;const open=e=>{e.preventDefault();e.stopPropagation();const u=new URL(matches[0].route_url,location.href);u.searchParams.set('rc_view','chat');u.searchParams.set('rc_kind','person');u.searchParams.set('rc_id',row.dataset.person);u.searchParams.set('rc_parent',matches[0].department_code);u.searchParams.set('rc_notice',matches[0].id);location.href=u.href;};badge.onclick=open;badge.onkeydown=e=>{if(e.key==='Enter'||e.key===' ')open(e)};}});
  const root=document.getElementById('messages');if(root&&context&&['group','person'].includes(context.kind)){root.querySelectorAll('[data-unread-bubble="card"]').forEach(b=>b.remove());const counts=new Map();for(const n of notices){if(new URL(n.route_url,location.href).searchParams.get('rc_status')!==context.status||n.department_code!==String(context.parentDepartment||context.id||'').toUpperCase()||context.kind==='person'&&!belongs(n,context.id))continue;const node=target(n);if(node)counts.set(node,(counts.get(node)||0)+1);}for(const [node,count]of counts)bubble(node.querySelector('h2,b')||node,count,'card');}
  document.getElementById('rrApprovalBadge71')?.remove();
  document.getElementById('rrInboxSummary71')?.remove();
 }
 function target(n){const root=document.getElementById('messages');if(!root)return null;const route=new URL(n.route_url,location.href),request=route.searchParams.get('rc_login_request');
  if(request)return [...root.querySelectorAll('[data-login-request]')].find(x=>x.dataset.loginRequest===request)?.closest('[data-customer-permission]')||null;
  if(n.action_detail?.journey_id||n.action_detail?.rectification_case_id){const key=n.action_detail.journey_id?'ALTER:'+n.action_detail.journey_id:'RECTIFICATION:'+n.action_detail.rectification_case_id;return [...root.querySelectorAll('[data-event-key]')].find(x=>x.dataset.eventKey===key)||null;}if(n.submit_request_id){const exact=[...root.querySelectorAll('[data-submit-request-id]')].find(x=>x.dataset.submitRequestId===n.submit_request_id);if(exact)return exact;}
  if(n.assignment_id){const exact=[...root.querySelectorAll('[data-assignment-id]')].find(x=>x.dataset.assignmentId===n.assignment_id);if(exact)return exact;const consolidated=[...root.querySelectorAll('[data-assignment-ids]')].find(x=>{try{return JSON.parse(x.dataset.assignmentIds).includes(n.assignment_id)}catch(_){return false}});if(consolidated)return consolidated;}
  if(n.event_key){const exact=[...root.querySelectorAll('[data-event-key]')].find(x=>x.dataset.eventKey===n.event_key);if(exact)return exact;}
  if(n.cb_unit_id)return [...root.querySelectorAll('[data-cb-unit-id]')].find(x=>x.dataset.cbUnitId===String(n.cb_unit_id))||null;
  if(n.cb_no)return [...root.querySelectorAll('[data-cb-no]')].find(x=>x.dataset.cbNo===n.cb_no)||null;
  if(n.event_key){const combined=[...root.querySelectorAll('[data-source-event-keys]')].find(x=>{try{return JSON.parse(x.dataset.sourceEventKeys).includes(n.event_key)}catch(_){return false}});if(combined)return combined;}
  // A targeted UPM notice must never focus another assignment sharing its lot.
  if(n.assignment_id||n.submit_request_id)return null;
  if(n.lot_no)return [...root.querySelectorAll('.work-card,.closed-row,[data-lot]')].find(x=>String(x.dataset.noticeLot||x.dataset.lot||'')===String(n.lot_no))||null;
  return null;
 }
 async function visible(){if(reading||document.hidden||!ready())return;
  const context=window.RRAdminApprovalHost71?.context(),chat=document.getElementById('chat');if(!context||chat?.hidden||!['group','person'].includes(context.kind))return;
  const requested=notices.find(n=>n.id===noticeId);
  if(requested&&!focusDone&&new URL(requested.route_url,location.href).searchParams.get('rc_status')===context.status&&window.RRAdminApprovalHost71?.focusNotice?.(requested))return;
  window.RRActionReceipts71?.render();
  await window.RRActionReceipts71?.visibleCards();
  const shown=notices.filter(n=>{const u=new URL(n.route_url,location.href);return n.department_code===String(context.parentDepartment||context.id||'').toUpperCase()&&(context.kind!=='person'||belongs(n,context.id))&&u.searchParams.get('rc_status')===context.status&&target(n)});
  const pinned=(q.get('rc_assignment')||q.get('rc_submit'))&&q.get('rc_parent')===String(context.parentDepartment||context.id||'').toUpperCase()&&q.get('rc_status')===context.status?{assignment_id:q.get('rc_assignment'),submit_request_id:q.get('rc_submit'),route_url:location.href}:null;
  const focus=shown.find(n=>n.id===noticeId||bridgeId&&String(n.bridge_id)===bridgeId)||(pinned&&target(pinned)?pinned:null);
  if(focus&&!focusDone){focusedNotice=focus;const node=window.RRActionReceipts71?.entry(focus)||target(focus);const closed=node.closest?.('details');if(closed)closed.open=true;node.setAttribute('tabindex','-1');node.classList.add('rrNoticeFocus71');node.scrollIntoView({block:'center',behavior:'auto'});node.focus({preventScroll:true});focusDone=true;}
  // Read only cards actually in the viewport; opening a department does not clear unseen cards.
  const ids=shown.filter(n=>{const node=window.RRActionReceipts71?window.RRActionReceipts71.entry(n):target(n);if(!node||node.closest('details:not([open])')||document.querySelector('dialog[open],.rf794-back.on,.sheetback.on'))return false;const r=node.getBoundingClientRect(),box=chat.getBoundingClientRect(),top=Math.max(r.top,box.top,0),bottom=Math.min(r.bottom,box.bottom,innerHeight);return window.RRActionReceipts71?r.width>0&&bottom-top>=Math.min(40,r.height*0.5):r.top<box.bottom&&r.bottom>box.top;}).map(n=>n.id);
  if(!ids.length)return;reading=true;
  try{
   const keys=notices.filter(n=>ids.includes(n.id)).map(n=>n.action_key||n.id);
   const changed=await rpc('rr_chat_notification_read_test71',{p_ids:ids});let confirmed=ids;
   if(!changed){
    const result=await rpc('rr_chat_notification_inbox_test71');
    if(!Array.isArray(result))return;
    confirmed=ids.filter(id=>!result.some(n=>n.id===id));
    notices=result.filter(n=>!confirmedReads.has(n.id));
   }else notices=notices.filter(n=>!ids.includes(n.id));
   confirmed.forEach(id=>confirmedReads.add(id));paint();
   if(confirmed.length){await window.RRActionReceipts71?.readConfirmed(confirmed,keys);navigator.serviceWorker?.controller?.postMessage({type:'RZ_NOTICE_READ71',ids:confirmed});}
   window.RRActionReceipts71?.render();paint();
  }catch(e){console.warn('Chat read status unavailable',e)}finally{reading=false}
 }
 async function refresh(){if(busy||!ready())return;busy=true;try{
  await Promise.allSettled([
   rpc('rr_chat_notification_inbox_test71').then(result=>{notices=(Array.isArray(result)?result:[]).filter(n=>!confirmedReads.has(n.id));paint();}).catch(e=>console.warn('Action unread counts unavailable',e)),
   rpc('rr_chat_staff_unread_test71').then(result=>{customers=Array.isArray(result)?result:[];paint();}).catch(e=>console.warn('Customer unread counts unavailable',e))
  ]);if(window.RRActionReceipts71&&notices.length)await rpc('rr_chat_action_delivered_test71',{p_ids:notices.map(n=>n.id)}).catch(e=>console.warn('Delivery status unavailable',e));await window.RRActionReceipts71?.refresh();const pending=notices.find(n=>n.id===noticeId);const context=window.RRAdminApprovalHost71?.context();if(pending&&context&&['group','person'].includes(context.kind)){const u=new URL(pending.route_url,location.href);if(u.searchParams.get('rc_status')!==context.status){u.searchParams.set('rc_notice',pending.id);if(context.kind==='person'){u.searchParams.set('rc_view','chat');u.searchParams.set('rc_kind','person');u.searchParams.set('rc_id',context.id);}location.replace(u.href);return;}}await visible();
 }finally{busy=false}}

 window.RRChatNotifications71={refresh,visible,paint,target,rpc,unread:()=>notices};
 document.addEventListener('scroll',()=>visible(),true);setInterval(()=>{if(!document.hidden){paint();refresh()}},3000);document.addEventListener('visibilitychange',()=>{if(!document.hidden)refresh()});setTimeout(refresh,1000);
})();
