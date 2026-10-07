(()=>{'use strict';
 if(window.RRChatNotifications71)return;
 let notices=[],customers=[],busy=false,reading=false,focusDone=false;
 const q=new URLSearchParams(location.search),noticeId=q.get('rc_notice'),bridgeId=q.get('rc_bridge');
 const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const style=document.createElement('style');style.textContent='.rrMsgBubble71{display:inline-flex;align-items:center;justify-content:center;min-width:25px;height:25px;padding:0 7px;margin-left:8px;border-radius:999px;background:#25a85a;color:white;font:800 13px system-ui;flex-shrink:0}.rrNoticeFocus71{outline:3px solid #ffe095!important;scroll-margin:24px}';document.head.appendChild(style);
 function bubble(host,n,key){if(!host)return;let b=host.querySelector('[data-unread-bubble="'+key+'"]');if(!n){b?.remove();return}if(!b){b=document.createElement('span');b.className='rrMsgBubble71';b.dataset.unreadBubble=key;host.appendChild(b)}const value=String(n);if(b.textContent!==value)b.textContent=value;b.setAttribute('aria-label',value+' unread messages')}
 function paint(){
  const byDept=new Map();for(const n of notices)byDept.set(n.department_code,(byDept.get(n.department_code)||0)+1);
  const customerTotal=customers.reduce((n,x)=>n+Number(x.unread_count||0),0);
  // Customer conversations belong to the Sales customer-chat engine, not work-card counts.
  byDept.set('SALES',(byDept.get('SALES')||0)+customerTotal);
  const total=notices.length+customerTotal;bubble(document.querySelector('#inbox .head h1'),total,'total');try{const result=total?navigator.setAppBadge?.(total):navigator.clearAppBadge?.();result?.catch(()=>{});}catch(_){}
  document.querySelectorAll('[data-department],[data-dept-group]').forEach(row=>{const dep=String(row.dataset.department||row.dataset.deptGroup).toUpperCase();bubble(row.querySelector('b'),byDept.get(dep)||0,'department');const badge=row.querySelector('[data-unread-bubble="department"]');if(badge){badge.setAttribute('role','button');badge.tabIndex=0;const open=event=>{event.preventDefault();event.stopPropagation();const first=notices.find(n=>n.department_code===dep);if(first)location.href=first.route_url+(first.route_url.includes('?')?'&':'?')+'rc_notice='+encodeURIComponent(first.id);else if(dep==='SALES'&&customers.find(n=>Number(n.unread_count)>0))location.href='real-sales-live-chat-v9434.html?chat='+encodeURIComponent(customers.find(n=>Number(n.unread_count)>0).chat_id);};badge.onclick=open;badge.onkeydown=e=>{if(e.key==='Enter'||e.key===' ')open(e)};}});
  document.getElementById('rrApprovalBadge71')?.remove();
  document.getElementById('rrInboxSummary71')?.remove();
 }
 function target(n){const root=document.getElementById('messages');if(!root)return null;const route=new URL(n.route_url,location.href),request=route.searchParams.get('rc_login_request');
  if(request)return [...root.querySelectorAll('[data-login-request]')].find(x=>x.dataset.loginRequest===request)?.closest('[data-customer-permission]')||null;
  if(n.event_key){const exact=[...root.querySelectorAll('[data-event-key]')].find(x=>x.dataset.eventKey===n.event_key);if(exact)return exact;}
  if(n.cb_no)return [...root.querySelectorAll('[data-cb-no]')].find(x=>x.dataset.cbNo===n.cb_no)||null;
  if(n.lot_no)return [...root.querySelectorAll('.work-card,.closed-row,[data-lot]')].find(x=>String(x.dataset.noticeLot||x.dataset.lot||'')===String(n.lot_no))||null;
  return null;
 }
 async function visible(){if(reading||document.hidden||!window.RF853?.rpc)return;
  const context=window.RRAdminApprovalHost71?.context(),chat=document.getElementById('chat');if(!context||chat?.hidden||!['group','person'].includes(context.kind))return;
  const shown=notices.filter(n=>{const u=new URL(n.route_url,location.href);return n.department_code===String(context.parentDepartment||context.id||'').toUpperCase()&&u.searchParams.get('rc_status')===context.status&&target(n)});
  const focus=shown.find(n=>n.id===noticeId||bridgeId&&String(n.bridge_id)===bridgeId);
  if(focus&&!focusDone){const node=target(focus);const closed=node.closest?.('details');if(closed)closed.open=true;node.setAttribute('tabindex','-1');node.classList.add('rrNoticeFocus71');node.scrollIntoView({block:'center',behavior:'auto'});node.focus({preventScroll:true});focusDone=true;}
  // Read only cards actually in the viewport; opening a department does not clear unseen cards.
  const ids=shown.filter(n=>{const r=target(n).getBoundingClientRect(),box=chat.getBoundingClientRect();return r.top<box.bottom&&r.bottom>box.top}).map(n=>n.id);
  if(!ids.length)return;reading=true;try{await RF853.rpc('rr_chat_notification_read_test71',{p_ids:ids});notices=notices.filter(n=>!ids.includes(n.id));navigator.serviceWorker?.controller?.postMessage({type:'RZ_NOTICE_READ71',ids});paint()}catch(e){console.warn('Chat read status unavailable',e)}finally{reading=false}
 }
 async function refresh(){if(busy||!window.RF853?.rpc)return;busy=true;try{const result=await RF853.rpc('rr_chat_notification_inbox_test71');notices=Array.isArray(result)?result:[];try{const rows=await RF853.rpc('rr_chat_staff_unread_test71');customers=Array.isArray(rows)?rows:[]}catch(_){}paint();await visible()}catch(e){console.warn('Chat unread counts unavailable',e)}finally{busy=false}}
 window.RRChatNotifications71={refresh,visible,paint};
 document.addEventListener('scroll',()=>visible(),true);setInterval(()=>{if(!document.hidden){paint();refresh()}},3000);document.addEventListener('visibilitychange',()=>{if(!document.hidden)refresh()});setTimeout(refresh,1000);
})();
