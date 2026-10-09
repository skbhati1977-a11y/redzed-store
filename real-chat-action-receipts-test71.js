(()=>{'use strict';
 let rows=[],key='',busy=false,popup=null,loadingPopup=false,returnFocus=null;
 const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const when=s=>s?new Date(s).toLocaleString('en-IN'):'—';
 const context=()=>window.RRAdminApprovalHost71?.context();
 const contextKey=c=>c&&['group','person'].includes(c.kind)?[c.parentDepartment||c.id,c.kind,c.id,c.status].join('|'):'';
 const rpc=(n,a)=>window.RRChatNotifications71.rpc(n,a);
 function state(recipients,ownRead=false,ownAction=false){const total=recipients.length,read=recipients.filter(r=>r.read_at).length,delivered=recipients.filter(r=>r.delivered_at||r.read_at).length,allRead=total>0&&read===total;return {total,read,label:allRead?'Read':delivered===total&&total?'Delivered':'Sent',red:!!ownAction,blue:!!ownRead&&!allRead&&!ownAction,green:allRead&&!ownAction};}
 function ownAction(row){const user=context()?.userId;return !!user&&row.actor_user_id===user;}
 function tick(row){const acted=ownAction(row),ownRead=acted||!!row.viewer_read_at||(row.recipients||[]).some(r=>r.recipient_id===context()?.userId&&r.read_at);const s=state(row.recipients||[],ownRead,acted);return '<button type="button" class="rrActionTick71 '+(s.red?'action-taken':s.green?'all-read':s.blue?'read':'')+'" data-action-receipt="'+esc(row.action_key)+'" aria-label="Read details: '+esc(row.action_label)+'">'+(s.label==='Sent'&&!ownRead?'✓':'✓✓')+' <small>'+(s.red?'Action taken':s.green?'All read':s.blue?'Read':'Read '+s.read+'/'+s.total)+'</small></button>';}
 function participantState(recipient,row){if(row?.actor_user_id&&recipient.recipient_id===row.actor_user_id)return {className:'action-taken',ticks:'✓✓',label:'Action taken',time:row.action_detail?.occurred_at||row.created_at};if(recipient.read_at)return {className:'read',ticks:'✓✓',label:'Read',time:recipient.read_at};if(recipient.delivered_at)return {className:'delivered',ticks:'✓✓',label:'Delivered',time:recipient.delivered_at};return {className:'sent',ticks:'✓',label:'Sent',time:null};}
 function eligible(row,c){if(row.department_code!==String(c.parentDepartment||c.id).toUpperCase())return false;if(c.kind==='person'&&!(row.worker_ids||[]).includes(c.id))return false;return new URL(row.route_url,location.href).searchParams.get('rc_status')===c.status;}
 function render(){const c=context(),root=document.getElementById('messages');if(!root||contextKey(c)!==key)return;
  const unread=new Set(window.RRChatNotifications71.unread().map(n=>n.action_key||n.id));const wanted=new Set();
  root.querySelectorAll('[data-unmapped-actions]').forEach(el=>el.remove());
  for(const row of rows){if(!eligible(row,c))continue;const card=window.RRChatNotifications71.target(row);if(!card)continue;card.querySelectorAll('p .tick').forEach(el=>el.hidden=true);
   let host=card.querySelector('.rrActionHistory71');if(!host){host=document.createElement('section');host.className='rrActionHistory71';host.setAttribute('aria-label','Action history');card.appendChild(host);}
   wanted.add(row.action_key);let el=[...host.querySelectorAll('[data-action-key]')].find(e=>e.dataset.actionKey===row.action_key);
   if(!el){el=document.createElement('div');el.className='rrActionEntry71';el.dataset.actionKey=row.action_key;host.appendChild(el);}
   const isUnread=unread.has(row.action_key)||unread.has(row.id);
   const label=(row.action_label||row.title||'Work update').replace(/ · recovered$/i,'').replace(/_/g,' ');
   const html='<strong>'+esc(label)+'</strong>'+(ownAction(row)?'':'<span class="rrActionOwnState71 '+(isUnread?'rrActionNew71':'')+'">'+(row.viewer_is_recipient===false?'Sent':isUnread?'Unread':'Read')+'</span>')+tick(row);
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
 async function readConfirmed(ids,keys=[]){render();const affected=rows.filter(row=>ids.includes(row.id)||keys.includes(row.action_key));await Promise.allSettled(affected.map(async row=>{row.recipients=await rpc('rr_chat_action_receipts_test71',{p_event_key:row.action_key});}));render();}
 async function details(actionKey){if(loadingPopup)return;loadingPopup=true;returnFocus=document.activeElement;
  if(!popup){popup=document.createElement('dialog');popup.className='rrReadDetails71';document.body.appendChild(popup);popup.addEventListener('click',e=>{if(e.target.closest('[data-close-receipts]')){popup.close();returnFocus?.focus();}});}
  const row=rows.find(r=>r.action_key===actionKey);popup.innerHTML='<button type="button" data-close-receipts aria-label="Close">×</button><h3>'+esc(row?.action_label||'Read Details')+'</h3><p>Loading…</p>';if(!popup.open)popup.showModal();
  try{const result=await rpc('rr_chat_action_receipts_test71',{p_event_key:actionKey});if(row)row.recipients=result;
   const participants=Array.isArray(result)?result.slice():[];
   if(row?.actor_user_id&&!participants.some(r=>r.recipient_id===row.actor_user_id))participants.unshift({recipient_id:row.actor_user_id,worker_name:row.actor_name||'Action taker',role_code:''});
   popup.innerHTML='<button type="button" data-close-receipts aria-label="Close">×</button><h3>'+esc((row?.action_label||'Read Details').replace(/ · recovered$/i,''))+'</h3><p>Lot '+esc(row?.lot_no||'—')+' · '+esc(when(row?.action_detail?.occurred_at||row?.created_at))+'</p><ul class="rrParticipants71">'+participants.map(r=>{const s=participantState(r,row);return '<li><span>'+esc(r.worker_name)+(r.role_code?' · '+esc(r.role_code):'')+'</span><span class="rrParticipantTick71 '+s.className+'">'+s.ticks+' '+s.label+'</span>'+(s.time?'<small>'+esc(when(s.time))+'</small>':'')+'</li>';}).join('')+'</ul>';render();
  }catch(e){popup.querySelector('p').textContent='Read details could not load. Close and retry.';}finally{loadingPopup=false;}
 }
 const style=document.createElement('style');style.textContent='.rrActionHistory71{border-top:1px solid #415565;margin-top:12px;padding-top:8px}.rrActionEntry71{display:flex;align-items:center;flex-wrap:wrap;gap:8px;padding:8px;margin:4px 0;border-radius:8px;font-size:12px;overflow-wrap:anywhere}.rrActionEntry71>strong{flex:1;min-width:80px}.rrActionOwnState71{font-size:11px;color:#a8bdce}.rrActionEntry71.unread{background:#173d32;border-left:3px solid #25a85a}.rrActionEntry71>div{margin-top:5px;color:#bdcbd5}.rrActionNew71{color:#62e89a;font-weight:800}.rrActionTick71{background:transparent!important;color:#b7c2cf!important;font-size:15px!important;padding:4px!important;border:0!important;border-radius:6px!important}.rrActionTick71.read{color:#53bdff!important}.rrActionTick71.all-read{color:#62e89a!important}.rrActionTick71.action-taken{color:#ff6868!important}.rrActionTick71 small{font-size:12px}.rrReadDetails71{background:#112231;color:#eff6fc;border:1px solid #597184;border-radius:14px;width:min(90vw,440px);max-height:80vh;overflow:auto}.rrReadDetails71::backdrop{background:#0009}.rrReadDetails71 li{padding:8px 0}.rrParticipants71{list-style:none;padding:0}.rrParticipants71 li{display:flex;align-items:center;gap:8px;flex-wrap:wrap;border-bottom:1px solid #294159}.rrParticipants71 li>span:first-child{flex:1;min-width:100px}.rrParticipants71 small{flex-basis:100%;color:#96a9bd}.rrParticipantTick71{color:#b7c2cf;white-space:nowrap;font-size:13px}.rrParticipantTick71.read{color:#53bdff}.rrParticipantTick71.action-taken{color:#ff6868}.rrReadDetails71 [data-close-receipts]{float:right}';document.head.appendChild(style);
 document.addEventListener('click',e=>{const t=e.target.closest('[data-action-receipt]');if(t){e.preventDefault();e.stopPropagation();details(t.dataset.actionReceipt);}});
 window.RRActionReceipts71={refresh,render,entry,readConfirmed,state,participantState,details};
})();
