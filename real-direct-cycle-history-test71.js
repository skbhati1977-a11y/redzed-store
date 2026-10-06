(() => {
 'use strict';
 if(window.__RR_DIRECT_HISTORY_TEST71__)return;
 window.__RR_DIRECT_HISTORY_TEST71__=true;
 const staff=/real-sales-live-chat-v9434\.html$/i.test(location.pathname);
 const q=new URLSearchParams(location.search), token=q.get('t')||q.get('c');
 const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const chatId=()=>window.RRActiveSalesChat71?.()||document.getElementById('msgs')?.dataset.chatId||document.querySelector('#inboxRows .chatrow.on')?.dataset.chat||q.get('chat_id')||'';
 const date=v=>v?new Date(v).toLocaleString('en-IN',{day:'2-digit',month:'short',hour:'2-digit',minute:'2-digit'}):'—';
 let state=null,activeChat='',busy=false,version=0,returnFocused=false;
 const style=document.createElement('style');
 style.textContent=`
 .rrCollectionReturnFocus71{outline:3px solid #65b5ff!important;box-shadow:0 0 24px #65b5ff88!important}.rrCollectionReturnFocus71 .rrLiveBelt71{background:#dcedff!important}.rrCycleLive71{box-sizing:border-box;padding:8px 12px;border-top:1px solid #40536b;background:#111d29;color:#edf3fa;max-height:180px;overflow:auto;font-size:11px;line-height:1.4}
 .rrLiveBelt71{display:block!important;width:100%!important;box-sizing:border-box!important;margin:0!important;background:#fff!important;color:#111!important;text-align:left!important;border-radius:10px!important;padding:8px 10px!important}
 .rrLiveBelt71 b,.rrLiveBelt71 small{display:block!important;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
 .rrLiveBelt71 small{color:#526174!important;font-size:9px!important;font-weight:400!important}
 .rrLiveDetail71{position:fixed;inset:0;z-index:12100;background:#000b;display:flex;align-items:flex-end}
 .rrLiveDetail71>section{width:100%;max-height:75dvh;overflow:auto;background:#111d29;color:#fff;border-radius:16px 16px 0 0;padding:15px;box-sizing:border-box}
 .rrCycleLive71 b{font-size:12px}.rrCycleLive71 small{font-size:10px;color:#a8b8ca}.rrCycleLive71 p{margin:3px 0;overflow-wrap:anywhere}
 .rrCycleLive71 .rrCycleStatus71{color:#8bd4ac;font-weight:700}.rrCycleLive71 button{border:1px solid #50647e;border-radius:7px;padding:6px 9px;background:#182535;color:#fff;font-size:11px;margin:4px 5px 0 0}
 #rrSalesCycleLive71{position:fixed;left:320px;right:0;z-index:10015;bottom:70px}
 #msgs{min-height:0;scroll-padding-bottom:24px}#msgs>.msg{flex-shrink:0}
 #rrFSChat #fsCollectionCard{display:none!important}
 .rrCycleLive71 details{margin-top:4px}.rrCycleLive71 summary{cursor:pointer;color:#aec9e6}
 @media(max-width:760px){#rrSalesCycleLive71{left:0}}
 `;
 document.head.appendChild(style);
 function panel(){
  const id=staff?'rrSalesCycleLive71':'rrCustomerCycleLive71';
  let host=document.getElementById(id);
  if(!host){const parent=staff?document.querySelector('.chat'):document.querySelector('#rrFSChat .fscompWrap');if(!parent)return null;host=document.createElement('section');host.id=id;host.className='rrCycleLive71';parent.prepend(host);}
  return host;
 }
 function markup(data){
  const cats=data.requested_categories||data.categories||[];
  const req=data.requirement_display_no||'REQUIREMENT · अभी नहीं आई';
  const history=(data.update_history||[]).map(e=>'<p>'+esc(e.kind)+' · UPDATE '+Number(e.update_no||0)+' · '+esc(date(e.created_at))+'</p>').join('');
  return '<b>'+esc(data.collection_display_no)+' · UPDATE '+Number(data.collection_update_no||0)+'</b>'+
   '<p><small>LAST COLLECTION · '+esc(date(data.last_collection_at))+'</small></p>'+
   '<p><b>'+esc(req)+(data.requirement_display_no?' · UPDATE '+Number(data.requirement_update_no||0):'')+'</b></p>'+
   '<p><small>LAST REQUIREMENT · '+esc(date(data.last_requirement_at))+'</small></p>'+
   (cats.length?'<p>CATEGORIES · '+cats.map(esc).join(' / ')+'<br><small>REQUEST UPDATE '+Number(data.sample_request_update_no||0)+' · '+esc(date(data.last_category_request_at))+'</small></p>':'')+
   '<p class="rrCycleStatus71">'+esc(data.live_status||String(data.collection_status||'').replaceAll('_',' '))+
   (data.pi_no?' · '+esc(data.pi_no)+' · '+esc(date(data.pi_generated_at)):'')+
   (data.ci_no?' · '+esc(data.ci_no)+' · '+esc(date(data.ci_generated_at)):'')+'</p>'+
   (staff?(data.requirement_id?'<button type="button" data-live-action="requirement">VIEW REQUIREMENT / PI</button>':'')+
    '<button type="button" data-live-action="collection">'+(data.can_send?'SELECT & SEND COLLECTION':'NEW COLLECTION')+'</button>':
    '<button type="button" data-live-action="collection">VIEW COLLECTION</button>')+
   (history?'<details><summary>UPDATE HISTORY</summary>'+history+'</details>':'');
 }
 function beltMarkup(data){
  const req=data.requirement_display_no?data.requirement_display_no+' · U'+Number(data.requirement_update_no||0):'REQ PENDING';
  const requestTime=data.last_requirement_at||data.last_category_request_at;
  return '<button type="button" class="rrLiveBelt71" data-live-action="details"><b>'+esc(data.collection_display_no)+' · U'+Number(data.collection_update_no||0)+' · '+esc(req)+'</b><small>COL '+esc(date(data.last_collection_at))+' · REQ '+esc(date(requestTime))+'</small><small>'+esc(data.live_status||String(data.collection_status||'').replaceAll('_',' '))+(data.sample_request_update_no?' · CATEGORY REQUEST U'+Number(data.sample_request_update_no):'')+(data.pi_no?' · '+esc(data.pi_no):'')+(data.ci_no?' · '+esc(data.ci_no):'')+' · OPEN ›</small></button>';
 }
 function showDetails(){
  document.getElementById('rrLiveDetail71')?.remove();
  const sheet=document.createElement('div');sheet.id='rrLiveDetail71';sheet.className='rrLiveDetail71';
  sheet.innerHTML='<section class="rrCycleLive71"><button type="button" data-live-action="close">CLOSE ×</button>'+markup(state)+'</section>';document.body.appendChild(sheet);
  sheet.onclick=e=>{if(e.target===sheet)sheet.remove();};
 }
 function measure(){
  if(!staff)return;const host=document.getElementById('rrSalesCycleLive71'),compose=document.querySelector('.compose'),msgs=document.getElementById('msgs');
  if(!host||!compose||!msgs)return;
  const bottom=Math.max(0,innerHeight-compose.getBoundingClientRect().top);
  host.style.bottom=bottom+'px';const reserved=bottom+(host.hidden?0:host.offsetHeight);msgs.style.marginBottom=reserved+'px';msgs.style.paddingBottom='24px';
 }
 function focusReturnedCollection(host){
  if(returnFocused||!staff||!(q.get('focus_message_id')||q.get('focus_collection')==='1')||host.hidden)return;
  if(chatId()!==q.get('chat_id')||String(state?.collection_cycle_id)!==q.get('collection_cycle_id'))return;
  requestAnimationFrame(()=>{
   if(returnFocused||host.hidden||chatId()!==q.get('chat_id')||String(state?.collection_cycle_id)!==q.get('collection_cycle_id'))return;
   const button=host.querySelector('.rrLiveBelt71');if(!button)return;
   returnFocused=true;host.classList.add('rrCollectionReturnFocus71');button.focus({preventScroll:true});
   const flash=document.getElementById('flash');if(flash){flash.textContent=(q.get('collection_notice')==='existing'?'Existing collection · selected designs already sent or outside requested categories · ':'Collection sent ✓ · ')+String(state.collection_display_no||'')+' · UPDATE '+Number(state.collection_update_no||0);flash.style.display='block';setTimeout(()=>{flash.style.display='none'},3500);}
   setTimeout(()=>host.classList.remove('rrCollectionReturnFocus71'),6000);
  });
 }
 function paint(){
  const host=panel();if(!host)return;
  const privateView=staff&&window.RRSalesChatActions71?.context()?.channel!=='GROUP';
  host.hidden=!state?.collection_cycle_id||privateView;
  if(host.hidden){measure();return;}
  host.dataset.cycleId=String(state.collection_cycle_id);
  const html=beltMarkup(state);
  if(host._html!==html){const open=!!host.querySelector('details[open]');host.innerHTML=html;host._html=html;if(open)host.querySelector('details')?.setAttribute('open','');const sheet=document.getElementById('rrLiveDetail71');if(sheet)sheet.querySelector('section').innerHTML='<button type="button" data-live-action="close">CLOSE ×</button>'+markup(state);}
  // Consolidated workflow history lives in this dock; normal messages remain in the stream.
  document.querySelectorAll(staff?'#msgs .msg':'#fsMsgs .fsm').forEach(row=>{
   if(staff&&row.querySelector('.rrMarketLinkCard9505')){row.style.removeProperty('display');return;}
   if(staff&&row.querySelector('.rrReqCard9508')){row.style.setProperty('display','none','important');return;}
   if(!row.dataset.rrCycle71)return;
   if(row.dataset.rrWorkflow71==='1'||['COLLECTION','REQUIREMENT','CATEGORY'].includes(row.dataset.rrWorkflow71))row.style.setProperty('display','none','important');
  });
  document.querySelectorAll('.rrCycleHistory71').forEach(el=>el.remove());
  measure();focusReturnedCollection(host);
 }
 async function refresh(){
  if(busy||!window.RF853?.rpc||(staff&&!chatId()))return;
  busy=true;const chat=chatId(),run=++version;
  try{
   const exactCycle=staff&&chat===q.get('chat_id')?q.get('collection_cycle_id'):null;
   const data=await RF853.rpc(staff?(exactCycle?'rr_sales_collection_cycle_status_test71':'rr_sales_collection_live_status_test71'):'rr_collection_current_state_v9633',staff?{p_chat_id:chat,...(exactCycle?{p_collection_cycle_id:exactCycle}:{})}:{p_token:token});
   if(run!==version||(staff&&chat!==chatId()))return;
   state=data;activeChat=chat;paint();
  }catch(e){const host=panel();if(host&&(!staff||chat===chatId())){host.hidden=false;host.textContent='Live status load नहीं हुआ। दोबारा कोशिश करें।';host._html='';measure();}}
  finally{busy=false;}
 }
 document.addEventListener('click',e=>{
  const action=e.target.closest?.('.rrCycleLive71 [data-live-action]');if(!action||!state)return;
  e.preventDefault();
  if(action.dataset.liveAction==='details'){
   if(staff&&state.latest_collection_token&&window.RRStaffCollectionViewer71){const u=new URL('s.html',location.href);u.searchParams.set('t',state.latest_collection_token);window.RRStaffCollectionViewer71.open(u.href);}
   else if(staff)showDetails();
   else {const b=document.getElementById('fcReopen')||document.getElementById('fcOpen');if(state.latest_collection_token&&state.latest_collection_token!==token){const u=new URL('s.html',location.href);u.searchParams.set('t',state.latest_collection_token);u.searchParams.set('open','collection');location.href=u.href;}else b?.onclick?.();}
   return;
  }
  if(action.dataset.liveAction==='close'){document.getElementById('rrLiveDetail71')?.remove();return;}
  document.getElementById('rrLiveDetail71')?.remove();
  if(staff){
   if(action.dataset.liveAction==='requirement')window.RRRequirementDetail71?.open(state.requirement_id);
   else window.RRSalesCollection?.open(state.can_send?state.requirement_id:null,state.can_send?state.collection_cycle_id:null).catch(err=>alert(err.message));
  }else{
   // A new cycle gets its own share binding, while the previous record stays in history.
   if(state.latest_collection_token&&state.latest_collection_token!==token){const u=new URL('s.html',location.href);u.searchParams.set('t',state.latest_collection_token);u.searchParams.set('open','collection');location.href=u.href;return;}
   const b=document.getElementById('fcReopen')||document.getElementById('fcOpen');
   if(b?.onclick)b.onclick();
  }
 },true);
 function hook(){
  if(!window.RF853?.rpc||RF853.rpc.__rrHistory71)return;
  const base=RF853.rpc.bind(RF853);
  const wrapped=async(name,args={})=>{
   const data=await base(name,args);
   if(!staff&&name==='rr_collection_current_state_v9633'){state=data;setTimeout(()=>{paint();document.dispatchEvent(new CustomEvent('rr:v71-cycle-state',{detail:data}));},0);}
   if(staff&&/rr_chat_staff_messages_v/.test(name)&&Array.isArray(data)){
    const chat=args.p_chat_id;
    setTimeout(()=>{if(chat!==chatId())return;
     data.forEach(m=>{const row=document.querySelector('#msgs .msg[data-msg-id="'+CSS.escape(String(m.id))+'"]');if(row&&m.payload?.direct_collection_cycle_id){row.dataset.rrCycle71=m.payload.direct_collection_cycle_id;row.dataset.rrWorkflow71=m.payload.source==='DIRECT_MARKET_WINDOW'?'COLLECTION':m.payload.source==='DIRECT_CATEGORY_REQUEST_TEST71'?'CATEGORY':m.payload.source==='DIRECT_MARKET_REQUIREMENT'?'REQUIREMENT':'';}});
     if(activeChat!==chat){state=null;paint();}refresh();
    },80);
   }
   if(!staff&&/rr_chat_customer_messages/.test(name)&&Array.isArray(data)){
    setTimeout(()=>{data.forEach(m=>{const row=document.querySelector('#fsMsgs .fsm[data-msg-id="'+CSS.escape(String(m.id))+'"]');if(row&&m.payload?.direct_collection_cycle_id){row.dataset.rrCycle71=m.payload.direct_collection_cycle_id;row.dataset.rrWorkflow71=['DIRECT_MARKET_WINDOW','DIRECT_MARKET_REQUIREMENT','DIRECT_CATEGORY_REQUEST_TEST71'].includes(m.payload.source)?'1':'0';}});paint();},80);
   }
   return data;
  };wrapped.__rrHistory71=true;RF853.rpc=wrapped;
 }
 let pending=false;
 new MutationObserver(()=>{if(pending)return;pending=true;requestAnimationFrame(()=>{pending=false;if(staff&&activeChat&&activeChat!==chatId()){state=null;activeChat='';version++;}paint();});}).observe(document.body,{childList:true,subtree:true});
 ['rr:v9605-requirement-sent','rr:v9630-more-samples-requested','rr:v9630-customer-closed'].forEach(event=>document.addEventListener(event,()=>setTimeout(refresh,100)));
 window.addEventListener('resize',measure);
 document.addEventListener('visibilitychange',()=>{if(!document.hidden)refresh();});
 hook();refresh();
 setInterval(()=>{hook();if(!document.hidden)refresh();},5000);
})();
