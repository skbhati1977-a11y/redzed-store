(() => {
 'use strict';
 if(window.__RR_CHAT_REQUIREMENT_IDENTITY_V9682__)return;
 window.__RR_CHAT_REQUIREMENT_IDENTITY_V9682__=true;
 const chatId=()=>window.RRActiveSalesChat71?.()||document.getElementById('msgs')?.dataset.chatId||document.querySelector('#inboxRows .chatrow.on')?.dataset.chat||new URLSearchParams(location.search).get('chat_id')||'';
 let signature='',revision=0,scheduled=false;
 async function decorate(node){
  const button=node.querySelector('.rrReqCard9508'),id=button?.dataset.requirementId;
  const chat=chatId(),version=revision,key=chat+'|'+id+'|'+version;
  if(!id||!chat||node.dataset.rrIdentity9682===key||!window.RRRequirementDetail71)return;
  node.dataset.rrIdentity9682=key;
  try{
   const data=await RRRequirementDetail71.load(chat,id);
   if(!node.isConnected||chatId()!==chat||version!==revision)return;
   const title=button.querySelector('b'),small=button.querySelector('small');
   if(title && title.textContent!=='📋 '+(data.requirement_display_no||data.requirement_no||'REQUIREMENT'))title.textContent='📋 '+(data.requirement_display_no||data.requirement_no||'REQUIREMENT');
   if(small)small.textContent='SOURCE: '+(data.collection_display_no||'COLLECTION')+' · '+(Number(data.collection_update_no)>0?'UPDATE '+Number(data.collection_update_no):'ORIGINAL')+' · '+String(data.status||'REQUIREMENT RECEIVED').replaceAll('_',' ');
  }catch(_){if(node.dataset.rrIdentity9682===key)delete node.dataset.rrIdentity9682;}
 }
 function scan(){document.querySelectorAll('#msgs .msg').forEach(decorate);}
 function schedule(){if(scheduled)return;scheduled=true;setTimeout(()=>{scheduled=false;scan();},0);}
 function init(){
  const base=RF853.rpc.bind(RF853);
  RF853.rpc=async(name,args={})=>{
   const data=await base(name,args);
   // Signature includes query scope: a one-row polling response must not
   // invalidate the full-chat snapshot and start another fetch loop.
   if(/rr_chat_staff_messages_v/.test(name)&&Array.isArray(data)&&Number(args.p_limit||200)>1){
    const next=JSON.stringify([args.p_chat_id,data.map(m=>[m.id,m.created_at,m.payload?.requirement_update_no,m.payload?.sample_request_update_no])]);
    if(next!==signature){signature=next;revision++;window.RRRequirementDetail71?.clear();schedule();}
   }
   return data;
  };
  const style=document.createElement('style');style.textContent='.rrReqIdentity9682{padding:9px;margin-bottom:10px;border:1px solid #3f536b;border-radius:11px;background:#14202d}.rrReqIdentity9682 b,.rrReqIdentity9682 small{display:block}.rrReqIdentity9682 small{color:#9fb0c2;margin-top:3px}';document.head.appendChild(style);
  // Metadata decorates messages only. Detail rendering is owned by the
  // requirement loader, with no observer that rewrites its own sheet.
  const msgs=document.getElementById('msgs');if(msgs)new MutationObserver(schedule).observe(msgs,{childList:true,subtree:true});
  scan();
 }
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();
