(()=>{'use strict';
 let rows=[],key='',busy=false,popup=null,loadingPopup=false,returnFocus=null;
 const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const when=s=>s?new Date(s).toLocaleString('en-IN'):'—';
 const context=()=>window.RRAdminApprovalHost71?.context();
 const contextKey=c=>c&&['group','person'].includes(c.kind)?[c.parentDepartment||c.id,c.kind,c.id,c.status].join('|'):'';
 const rpc=(n,a)=>window.RRChatNotifications71.rpc(n,a);
 function state(recipients){const total=recipients.length,read=recipients.filter(r=>r.read_at).length,delivered=recipients.filter(r=>r.delivered_at||r.read_at).length;return {total,read,label:read===total&&total?'Read':delivered===total&&total?'Delivered':'Sent',blue:total>0&&read===total};}
 function tick(row){const s=state(row.recipients||[]);return '<button type="button" class="rrActionTick71 '+(s.blue?'read':'')+'" data-action-receipt="'+esc(row.action_key)+'" aria-label="Read details: '+esc(row.action_label)+'">'+(s.label==='Sent'?'✓':'✓✓')+' <small>Read '+s.read+'/'+s.total+'</small></button>';}
 function eligible(row,c){if(row.department_code!==String(c.parentDepartment||c.id).toUpperCase())return false;if(c.kind==='person'&&!(row.worker_ids||[]).includes(c.id))return false;return new URL(row.route_url,location.href).searchParams.get('rc_status')===c.status;}
 function render(){const c=context(),root=document.getElementById('messages');if(!root||contextKey(c)!==key)return;
  const unread=new Set(window.RRChatNotifications71.unread().map(n=>n.action_key||n.id));const wanted=new Set();
  for(const row of rows){if(!eligible(row,c))continue;let card=window.RRChatNotifications71.target(row);
   if(!card||card.closest('[data-unmapped-actions]')){card=root.querySelector('[data-unmapped-actions]');if(!card){card=document.createElement('section');card.dataset.unmappedActions='';card.innerHTML='<h3>Other action updates</h3><p>These events are outside the current work-card list.</p>';root.appendChild(card);}}
   let host=card.querySelector('.rrActionHistory71');if(!host){host=document.createElement('section');host.className='rrActionHistory71';host.setAttribute('aria-label','Action history');card.appendChild(host);}
   wanted.add(row.action_key);let el=[...host.querySelectorAll('[data-action-key]')].find(e=>e.dataset.actionKey===row.action_key);
   if(!el){el=document.createElement('div');el.className='rrActionEntry71';el.dataset.actionKey=row.action_key;host.appendChild(el);}
   const isUnread=unread.has(row.action_key)||unread.has(row.id),detail=Object.entries(row.action_detail||{}).filter(([k])=>!['source_verified','occurred_at'].includes(k)).filter(([,v])=>v!==null&&v!==undefined&&v!=='').map(([k,v])=>esc(k.replace(/_/g,' '))+': '+esc(v)).join(' · ');
   const html='<strong>'+esc(row.action_label||row.title||'Work update')+'</strong> '+(isUnread?'<span class="rrActionNew71">NEW</span>':'')+'<div>Lot '+esc(row.lot_no||'—')+' · '+esc(row.actor_name||'Actor not recorded')+' · '+esc(when(row.action_detail?.occurred_at||row.created_at))+'</div>'+(detail?'<div>'+detail+'</div>':'')+tick(row);
   if(el.innerHTML!==html)el.innerHTML=html;el.classList.toggle('unread',isUnread);el.dataset.noticeId=row.id;
  }
  root.querySelectorAll('[data-action-key]').forEach(el=>{if(!wanted.has(el.dataset.actionKey))el.remove();});
  root.querySelectorAll('.rrActionHistory71').forEach(el=>{if(!el.children.length)el.remove();});
 }
 async function refresh(){const c=context(),next=contextKey(c);if(!next){key='';rows=[];return;}if(busy)return;busy=true;
  try{const result=await rpc('rr_chat_action_history_test71',{p_department:String(c.parentDepartment||c.id).toUpperCase(),p_worker:c.kind==='person'?c.id:null});if(contextKey(context())!==next)return;key=next;rows=Array.isArray(result)?result:[];render();await window.RRChatNotifications71.visible();}
  catch(e){console.warn('Action history unavailable',e);}finally{busy=false;}
 }
 function entry(n){return [...document.querySelectorAll('#messages [data-action-key]')].find(e=>e.dataset.actionKey===(n.action_key||n.id))||null;}
 function readConfirmed(){render();}
 async function details(actionKey){if(loadingPopup)return;loadingPopup=true;returnFocus=document.activeElement;
  if(!popup){popup=document.createElement('dialog');popup.className='rrReadDetails71';document.body.appendChild(popup);popup.addEventListener('click',e=>{if(e.target.closest('[data-close-receipts]')){popup.close();returnFocus?.focus();}});}
  const row=rows.find(r=>r.action_key===actionKey);popup.innerHTML='<button type="button" data-close-receipts aria-label="Close">×</button><h3>'+esc(row?.action_label||'Read Details')+'</h3><p>Loading…</p>';if(!popup.open)popup.showModal();
  try{const result=await rpc('rr_chat_action_receipts_test71',{p_event_key:actionKey});if(row)row.recipients=result;const groups=[['READ',r=>r.read_at],['UNREAD · Delivered',r=>!r.read_at&&r.delivered_at],['UNREAD · Not delivered',r=>!r.read_at&&!r.delivered_at]];
   popup.innerHTML='<button type="button" data-close-receipts aria-label="Close">×</button><h3>'+esc(row?.action_label||'Read Details')+'</h3>'+groups.map(([title,filter])=>'<h4>'+title+'</h4><ul>'+result.filter(filter).map(r=>'<li>'+esc(r.worker_name)+' · '+esc(r.role_code)+'<br><small>'+(r.read_at?'✓✓ Read · '+esc(when(r.read_at)):r.delivered_at?'✓✓ Delivered · '+esc(when(r.delivered_at)):'✓ Not delivered')+'</small></li>').join('')+'</ul>').join('');render();
  }catch(e){popup.querySelector('p').textContent='Read details could not load. Close and retry.';}finally{loadingPopup=false;}
 }
 const style=document.createElement('style');style.textContent='.rrActionHistory71{border-top:1px solid #415565;margin-top:12px;padding-top:8px}.rrActionEntry71{padding:10px 8px;margin:6px 0;border-radius:8px;font-size:14px;overflow-wrap:anywhere}.rrActionEntry71.unread{background:#173d32;border-left:3px solid #25a85a}.rrActionEntry71>div{margin-top:5px;color:#bdcbd5}.rrActionNew71{color:#62e89a;font-weight:800}.rrActionTick71{background:transparent!important;color:#b7c2cf!important;font-size:18px!important;padding:6px!important}.rrActionTick71.read{color:#53bdff!important}.rrActionTick71 small{font-size:12px}.rrReadDetails71{background:#112231;color:#eff6fc;border:1px solid #597184;border-radius:14px;width:min(90vw,440px);max-height:80vh;overflow:auto}.rrReadDetails71::backdrop{background:#0009}.rrReadDetails71 li{padding:8px 0}.rrReadDetails71 h4:first-of-type,.rrReadDetails71 h4:first-of-type+ul{color:#53bdff}.rrReadDetails71 [data-close-receipts]{float:right}';document.head.appendChild(style);
 document.addEventListener('click',e=>{const t=e.target.closest('[data-action-receipt]');if(t){e.preventDefault();e.stopPropagation();details(t.dataset.actionReceipt);}});
 window.RRActionReceipts71={refresh,render,entry,readConfirmed,state,details};
})();
