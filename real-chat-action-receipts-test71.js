(()=>{'use strict';
 const snapshots=new Map(); let rows=[],key='',busy=false,refreshSeq=0,readingCards=false,popup=null,loadingPopup=false,returnFocus=null;
 const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const when=s=>s?new Date(s).toLocaleString('en-IN'):'—';
 const context=()=>window.RRAdminApprovalHost71?.context();
 const contextKey=c=>c&&['group','person'].includes(c.kind)?[c.parentDepartment||c.id,c.kind,c.id,c.status,c.userId||'',window.RR_VIEW_AS_ACTOR_ID||''].join('|'):'';
 const rpc=(n,a)=>window.RRChatNotifications71.rpc(n,a);
 function state(recipients,ownRead=false,ownAction=false){const total=recipients.length,read=recipients.filter(r=>r.read_at).length,delivered=recipients.filter(r=>r.delivered_at||r.read_at).length,allRead=total>0&&read===total;return {total,read,label:allRead?'Read':delivered===total&&total?'Delivered':'Sent',red:!!ownAction,blue:!!ownRead&&!allRead&&!ownAction,green:allRead&&!ownAction};}
 function ownAction(row){const user=context()?.userId;return !!user&&row.actor_user_id===user;}
 function pendingHandoverLabel(row,value,card){return card?.dataset.acceptCountComplete==='false'&&/LM[_ ]ACCEPTED|RECEIVER[_ ]ACCEPTED|FABRICATION[_ ]SHARED[_ ]CLAIM/i.test(String(value||''))?'Submit · Accept & Count pending':value;}
 function actionDescription71(value){
  const label=String(value||'Action taken').replace(/ · recovered$/i,'').replace(/_/g,' ').replace(/\s+/g,' ').trim();
  if(/Accept.*Count.*pending|Count.*बाकी|NOT ACCEPTED/i.test(label))return 'Accept & Count pending';
  if(/LM ACCEPTED|RECEIVER ACCEPTED|FABRICATION SHARED CLAIM/i.test(label))return 'Accept & Count started';
  if(/HANDOVER COMPLETED|ACCEPT.*COUNT.*COMPLET/i.test(label))return 'Accept & Count completed';
  if(/RECTIF/i.test(label))return /CLOSE|COMPLET|RESOLV/i.test(label)?'Rectified':'Rectify started';
  if(/ALTER/i.test(label))return /SUBMIT/i.test(label)?'Alter submitted':/CLOSE|COMPLET/i.test(label)?'Alter completed':'Altered';
  if(/LOT.*RELEASE|CUTTING.*RELEASE/i.test(label))return 'Lot released';
  if(/SUBMIT/i.test(label))return 'Submitted';
  if(/ACCEPT.*COUNT|CONFIRM.*RECEI|RECEIPT.*CONFIRM/i.test(label))return 'Accept & Count completed';
  if(/ACCEPT/i.test(label))return 'Accepted';
  if(/ASSIGN/i.test(label))return 'Assigned';
  if(/APPROV/i.test(label))return 'Approved';
  if(/REJECT/i.test(label))return 'Rejected';
  if(/PAUS/i.test(label))return 'Paused';
  if(/REVOK/i.test(label))return 'Access revoked';
  if(/DISPATCH|DESPATCH/i.test(label))return 'Despatched';
  if(/DELIVER/i.test(label))return 'Delivered';
  if(/RECEIV/i.test(label))return 'Received';
  if(/SHAR/i.test(label))return 'Shared';
  if(/SENT|SEND/i.test(label))return 'Sent';
  if(/SAVE/i.test(label))return 'Saved';
  if(/UPDAT/i.test(label))return 'Updated';
  if(/CREAT/i.test(label))return 'Created';
  if(/CANCEL/i.test(label))return 'Cancelled';
  return label;
 }
 function pendingAction71(card){
  if(!card||context()?.status==='CLOSE')return '';
  const controls=[...card.querySelectorAll('.card-actions button,.card-actions a')].filter(e=>!e.disabled&&!e.hidden);
  const primary=(card.dataset.ratePending==='true'&&controls.find(e=>e.matches('[data-rate-popup]')))||controls.find(e=>e.matches('[data-fab-receive],[data-receipt-accept]'))||controls.find(e=>e.matches('[data-chat-submit]'))||controls.find(e=>e.matches('[data-assign-action]'))||controls.find(e=>e.matches('[data-rate-popup]'))||controls.find(e=>!e.matches('[data-chat-alter],[data-chat-rectify]'))||controls[0];
  if(!primary)return ({LM_ACCEPT:'ALTER ACCEPT',REMAKE_ISSUE:'REMAKE तैयार करें',RECEIVE_FROM_MASTER:'REMAKE प्राप्त करें',DELIVER_TO_KARIGAR:'WORKER को दें',KARIGAR_SUBMIT_GOOD:'ALTER SUBMIT',RECEIVE_FROM_KARIGAR:'ALTER प्राप्त करें',RECTIFICATION_CLOSE:'RECTIFY · FINAL CLOSE'})[card.dataset.requiredAction]||String(card.dataset.requiredAction||'').replace(/_/g,' ');
  if(primary.matches('[data-receipt-accept]')&&card.dataset.requiredAction==='ASSIGNED RECEIPT / COUNT')return 'ASSIGNED RECEIPT / COUNT';
  if(primary.matches('[data-fab-receive],[data-receipt-accept]'))return 'ACCEPT & COUNT';
  if(primary.matches('[data-chat-submit]'))return 'SUBMIT';
  if(primary.matches('[data-assign-action]'))return 'ASSIGN WORKER';
  if(primary.matches('[data-rate-popup]'))return 'FILL ACTUAL RATE';
  return primary.textContent.trim().replace(/\s+/g,' ');
 }
 function receiptHtmlMatches71(el,html){const pending=el.querySelector('.rrCardPending71');return (pending?el.innerHTML.replace(pending.outerHTML,''):el.innerHTML)===html;}
 function syncPendingActions71(root){
  root.querySelectorAll('article').forEach(card=>{
   const action=pendingAction71(card);let line=card.querySelector('.rrCardPending71');
   if(!action){line?.remove();return}
   if(!line){line=document.createElement('div');line.className='rrCardPending71';}
   const person=card.dataset.pendingPerson;const text='अगला action बाकी: '+action+(person?' · '+person:'')+' ✓✓';if(line.textContent!==text)line.textContent=text;
   const read=card.querySelector('.rrActionEntry71 .rrActionTick71');
   if(read){if(line.nextElementSibling!==read)read.before(line);}else if(line.parentElement!==card)card.appendChild(line);
  });
 }
 function tick(row,card,isUnread=false){
  const acted=ownAction(row),ownRead=acted||!!row.viewer_read_at||(row.recipients||[]).some(r=>r.recipient_id===context()?.userId&&r.read_at),s=state(row.recipients||[],ownRead,false);
  const label=s.green?'All read':s.blue?'Read':isUnread?'Unread':s.label==='Delivered'?'Delivered':'Sent';
  const description=actionDescription71(pendingHandoverLabel(row,row.actor_action_label||row.action_label||'Action taken',card));
  const subject=row.action_subject_name,person=subject||row.actor_name||'Action taker',by=subject&&row.actor_name&&subject.toLowerCase()!==row.actor_name.toLowerCase()?' ('+row.actor_name+')':'';
  const actor=row.actor_user_id||row.actor_name?'<span class="rrCardActor71"><span><small class="rrPreviousAction71">पिछला action: </small>'+esc(person)+esc(by)+' · '+esc(description)+'</span><span class="rrActorTick71" aria-label="Action taken">✓✓</span></span>':'<span class="rrCardAction71">'+esc(actionDescription71(pendingHandoverLabel(row,row.action_label||row.title||'Work update',card)))+'</span>';
  return actor+'<button type="button" class="rrActionTick71 '+(s.green?'all-read':s.blue?'read':'')+'" data-action-receipt="'+esc(row.action_key)+'" aria-label="Read details: '+esc(row.action_label)+'"><small class="'+(!acted?'rrActionOwnState71 ':'')+(isUnread&&!ownRead&&!s.green?'rrActionNew71':'')+'">'+esc(label)+'</small><span aria-hidden="true">'+(s.label==='Sent'&&!ownRead?'✓':'✓✓')+'</span></button>';
 }
 function participantState(recipient,row){if(row?.actor_user_id&&recipient.recipient_id===row.actor_user_id)return {className:'action-taken',ticks:'✓✓',label:'Action taken',time:row.action_detail?.occurred_at||row.created_at};if(recipient.read_at)return {className:'read',ticks:'✓✓',label:'Read',time:recipient.read_at};if(recipient.delivered_at)return {className:'delivered',ticks:'✓✓',label:'Delivered',time:recipient.delivered_at};return {className:'sent',ticks:'✓',label:'Sent',time:null};}
 function eligible(row,c){if(row.department_code!==String(c.parentDepartment||c.id).toUpperCase())return false;if(c.kind==='person'&&!(row.worker_ids||[]).includes(c.id))return false;return new URL(row.route_url,location.href).searchParams.get('rc_status')===c.status;}
 function render(){const c=context(),root=document.getElementById('messages');if(!root||contextKey(c)!==key)return;
  const unread=new Set(window.RRChatNotifications71.unread().map(n=>n.action_key||n.id));const wanted=new Set();
  root.querySelectorAll('[data-unmapped-actions]').forEach(el=>el.remove());
  for(const row of rows){if(row.card_receipt||!eligible(row,c))continue;const card=window.RRChatNotifications71.target(row);if(!card||card.dataset.stageFooter==='true'&&rows.some(r=>r.card_receipt&&eligible(r,c)&&window.RRChatNotifications71.target(r)===card))continue;card.querySelectorAll('p .tick').forEach(el=>el.hidden=true);
   let host=card.querySelector('.rrActionHistory71');if(!host){host=document.createElement('section');host.className='rrActionHistory71';host.setAttribute('aria-label','Action history');card.appendChild(host);}
   wanted.add(row.action_key);let el=[...host.querySelectorAll('[data-action-key]')].find(e=>e.dataset.actionKey===row.action_key);
   if(!el){el=document.createElement('div');el.className='rrActionEntry71';el.dataset.actionKey=row.action_key;host.appendChild(el);}
   const isUnread=unread.has(row.action_key)||unread.has(row.id);
   const html=tick(row,card,isUnread);
   if(!receiptHtmlMatches71(el,html))el.innerHTML=html;el.classList.toggle('unread',isUnread);el.dataset.noticeId=row.id;
  }
  for(const row of rows.filter(r=>r.card_receipt)){if(!eligible(row,c))continue;const card=window.RRChatNotifications71.target(row);if(!card||card.dataset.stageFooter!=='true'&&card.querySelector('.rrActionHistory71 [data-action-key]'))continue;
   card.querySelectorAll('p .tick').forEach(el=>el.hidden=true);wanted.add(row.action_key);
   let el=card.querySelector('.rrSourceCardReceipt71');if(!el){el=document.createElement('div');el.className='rrSourceCardReceipt71 rrActionEntry71';card.appendChild(el);}el.dataset.actionKey=row.action_key;
   const html=tick(row,card);if(!receiptHtmlMatches71(el,html))el.innerHTML=html;
  }
  root.querySelectorAll('[data-action-key]').forEach(el=>{if(!wanted.has(el.dataset.actionKey))el.remove();});
  root.querySelectorAll('.rrActionHistory71').forEach(el=>{if(!el.children.length)el.remove();});
  syncPendingActions71(root);
 }
 async function refresh(){const c=context(),next=contextKey(c);if(!next){key='';rows=[];return;}if(busy&&key===next)return;
  const seq=++refreshSeq;key=next;rows=snapshots.get(next)||[];render();busy=true;
  const args=sourceArgs(c);
  const accept=(result,source)=>{if(seq!==refreshSeq||contextKey(context())!==next||!Array.isArray(result))return;rows=rows.filter(r=>!!r.card_receipt!==source).concat(result);snapshots.set(next,rows);render();};
  try{await Promise.allSettled([rpc('rr_chat_action_history_test71',{p_department:args.p_department,p_worker:args.p_worker}).then(r=>accept(r,false)),rpc('rr_chat_source_card_receipts_test71',args).then(r=>accept(r,true))]);if(seq===refreshSeq)await window.RRChatNotifications71.visible();}
  finally{if(seq===refreshSeq)busy=false;}
 }
 function sourceArgs(c){return {p_department:String(c.parentDepartment||c.id).toUpperCase(),p_status:c.status,p_worker:c.kind==='person'?c.id:null,p_read_keys:[]};}
 async function visibleCards(){const c=context(),chat=document.getElementById('chat');if(readingCards||document.hidden||chat?.hidden||contextKey(c)!==key||document.querySelector('dialog[open],.rf794-back.on,.sheetback.on,.vendor-popup'))return;
  const keys=rows.filter(r=>r.card_receipt&&!r.viewer_read_at&&eligible(r,c)).filter(r=>{const node=entry(r);if(!node||node.closest('details:not([open])'))return false;const a=node.getBoundingClientRect(),b=chat.getBoundingClientRect();return a.width>0&&Math.min(a.bottom,b.bottom,innerHeight)-Math.max(a.top,b.top,0)>=Math.min(40,a.height*.5);}).map(r=>r.action_key);
  if(!keys.length)return;readingCards=true;const scope=key;try{const updated=await rpc('rr_chat_source_card_receipts_test71',{...sourceArgs(c),p_read_keys:keys});if(contextKey(context())!==scope||!Array.isArray(updated))return;rows=rows.filter(r=>!r.card_receipt).concat(updated);snapshots.set(scope,rows);render();}catch(e){console.warn('Card read status unavailable',e);}finally{readingCards=false;}
 }
 function entry(n){const exact=[...document.querySelectorAll('#messages [data-action-key]')].find(e=>e.dataset.actionKey===(n.action_key||n.id));if(exact)return exact;const c=context(),card=c&&eligible(n,c)?window.RRChatNotifications71.target(n):null;return card?.dataset.stageFooter==='true'?card.querySelector('.rrSourceCardReceipt71'):null;}
 async function readConfirmed(ids,keys=[]){render();const affected=rows.filter(row=>ids.includes(row.id)||keys.includes(row.action_key));await Promise.allSettled(affected.map(async row=>{row.recipients=await rpc('rr_chat_action_receipts_test71',{p_event_key:row.action_key});}));render();}
 async function details(actionKey){if(loadingPopup)return;loadingPopup=true;returnFocus=document.activeElement;
  if(!popup){popup=document.createElement('dialog');popup.className='rrReadDetails71';document.body.appendChild(popup);popup.addEventListener('click',e=>{if(e.target.closest('[data-close-receipts]')){popup.close();returnFocus?.focus();}});}
  const row=rows.find(r=>r.action_key===actionKey);popup.innerHTML='<button type="button" data-close-receipts aria-label="Close">×</button><h3>'+esc(row?.action_label||'Read Details')+'</h3><p>Loading…</p>';if(!popup.open)popup.showModal();
  try{const result=row?.card_receipt?(await rpc('rr_chat_source_card_receipts_test71',sourceArgs(context()))).find(r=>r.action_key===actionKey)?.recipients||[]:await rpc('rr_chat_action_receipts_test71',{p_event_key:actionKey});if(row)row.recipients=result;
   const participants=Array.isArray(result)?result.slice():[];
   if(row?.actor_user_id&&!participants.some(r=>r.recipient_id===row.actor_user_id))participants.unshift({recipient_id:row.actor_user_id,worker_name:row.actor_name||'Action taker',role_code:''});
   popup.innerHTML='<button type="button" data-close-receipts aria-label="Close">×</button><h3>'+esc((row?.action_label||'Read Details').replace(/ · recovered$/i,''))+'</h3><p>Lot '+esc(row?.lot_no||'—')+' · '+esc(when(row?.action_detail?.occurred_at||row?.created_at))+'</p><ul class="rrParticipants71">'+participants.map(r=>{const s=participantState(r,row);return '<li><span>'+esc(r.worker_name)+(r.role_code?' · '+esc(r.role_code):'')+'</span><span class="rrParticipantTick71 '+s.className+'">'+s.ticks+' '+s.label+'</span>'+(s.time?'<small>'+esc(when(s.time))+'</small>':'')+'</li>';}).join('')+'</ul>';render();
  }catch(e){popup.querySelector('p').textContent='Read details could not load. Close and retry.';}finally{loadingPopup=false;}
 }
 const style=document.createElement('style');style.textContent='.rrActionHistory71{border-top:1px solid #415565;margin-top:12px;padding-top:8px}.rrActionEntry71{display:flex;flex-direction:column;align-items:stretch;gap:6px;padding:8px;margin:4px 0;border-radius:8px;font-size:12px;overflow-wrap:anywhere}.rrActionEntry71>strong{flex:1;min-width:80px}.rrActionOwnState71{font-size:12px;color:inherit}.rrActionEntry71.unread{background:#173d32;border-left:3px solid #25a85a}.rrActionEntry71>div{margin-top:5px;color:#bdcbd5}.rrActionNew71{color:inherit;font-weight:800}.rrActionTick71{background:transparent!important;color:#b7c2cf!important;font-size:15px!important;padding:4px!important;border:0!important;border-radius:6px!important}.rrActionTick71.read{color:#53bdff!important}.rrActionTick71.all-read{color:#62e89a!important}.rrActionTick71.action-taken{color:#ff6868!important}.rrCardActor71,.rrCardAction71{display:flex;align-items:baseline;gap:8px;font-size:13px;line-height:1.5;color:#e5edf4}.rrCardActor71>span:first-child{min-width:0}.rrActorTick71{flex-shrink:0}.rrActionTick71{display:flex!important;align-items:baseline;align-self:flex-start;gap:8px;text-align:left;line-height:1.5!important}.rrActionTick71 small{color:inherit!important}.rrActorTick71{color:#ff6868;font-size:15px}.rrPreviousAction71{font-size:12px;color:#a8bdce}.rrActionEntry71>.rrCardPending71,.rrCardPending71{color:#ffd45a;font-size:13px;font-weight:700;line-height:1.5;padding:5px 0;overflow-wrap:anywhere}.rrActionTick71 small{font-size:12px}.rrReadDetails71{background:#112231;color:#eff6fc;border:1px solid #597184;border-radius:14px;width:min(90vw,440px);max-height:80vh;overflow:auto}.rrReadDetails71::backdrop{background:#0009}.rrReadDetails71 li{padding:8px 0}.rrParticipants71{list-style:none;padding:0}.rrParticipants71 li{display:flex;align-items:center;gap:8px;flex-wrap:wrap;border-bottom:1px solid #294159}.rrParticipants71 li>span:first-child{flex:1;min-width:100px}.rrParticipants71 small{flex-basis:100%;color:#96a9bd}.rrParticipantTick71{color:#b7c2cf;white-space:nowrap;font-size:13px}.rrParticipantTick71.read{color:#53bdff}.rrParticipantTick71.action-taken{color:#ff6868}.rrReadDetails71 [data-close-receipts]{float:right}';document.head.appendChild(style);
 document.addEventListener('click',e=>{const t=e.target.closest('[data-action-receipt]');if(t){e.preventDefault();e.stopPropagation();details(t.dataset.actionReceipt);}});
 window.RRActionReceipts71={refresh,render,entry,readConfirmed,visibleCards,state,participantState,details,actionDescription:actionDescription71,pendingAction:pendingAction71};
})();
