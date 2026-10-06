(()=>{'use strict';
 if(window.RRStaffUnread71)return;
 const $=id=>document.getElementById(id);let counts=new Map(),focus=null,busy=false;
 const style=document.createElement('style');style.textContent='.rrUnreadBadge71{float:right;border-radius:18px;padding:4px 9px;background:#2376cf;color:white;font-size:12px;font-weight:800}.rrUnreadSummary71{padding:10px 12px;color:#b8dcff;font-weight:700;border-bottom:1px solid #344559}.rrUnreadFocus71{outline:3px solid #66b7ff!important;scroll-margin:24px}';document.head.append(style);
 function paint(){
  let messages=0,chats=0;counts.forEach(row=>{const n=Number(row.unread_count||0);messages+=n;if(n>0)chats++});
  const host=$('inbox');if(host){let summary=$('rrUnreadSummary71');if(!summary){summary=document.createElement('div');summary.id='rrUnreadSummary71';summary.className='rrUnreadSummary71';host.insertBefore(summary,$('inboxRows'))}const label=messages+' unread messages · '+chats+' unread customer chats';if(summary.textContent!==label)summary.textContent=label;}
  document.querySelectorAll('#inboxRows [data-chat]').forEach(row=>{const n=Number(counts.get(row.dataset.chat)?.unread_count||0);let badge=row.querySelector('.rrUnreadBadge71');if(n){if(!badge){badge=document.createElement('span');badge.className='rrUnreadBadge71';row.querySelector('b')?.append(badge)}if(badge.textContent!==String(n))badge.textContent=String(n);badge.setAttribute('aria-label',n+' unread messages')}else badge?.remove()});
 }
 async function refresh(){if(busy||!window.RF853?.rpc)return;busy=true;try{const rows=await RF853.rpc('rr_chat_staff_unread_test71');counts=new Map((rows||[]).map(row=>[String(row.chat_id),row]));paint()}catch(error){console.warn('Unread status unavailable',error)}finally{busy=false}}
 async function prepare(chatId){await refresh();const row=counts.get(String(chatId));focus=row?.first_unread?{chatId,id:row.first_unread.id,message:row.first_unread}:null;}
 function rows(chatId,data){if(focus?.chatId!==chatId||data.some(m=>m.id===focus.id))return data;return [focus.message,...data];}
 function apply(chatId){if(focus?.chatId!==chatId)return false;const target=focus;focus=null;
  const position=()=>{if(window.RRActiveSalesChat71?.()!==chatId)return;let node=document.querySelector('#msgs [data-msg-id="'+CSS.escape(target.id)+'"]');if(node&&getComputedStyle(node).display==='none'&&target.message.payload?.direct_collection_cycle_id===document.getElementById('rrSalesCycleLive71')?.dataset.cycleId)node=document.querySelector('#rrSalesCycleLive71 .rrLiveBelt71');if(!node)return;node.scrollIntoView({block:'center',behavior:'auto'});node.classList.add('rrUnreadFocus71');node.setAttribute('tabindex','-1');node.focus({preventScroll:true});setTimeout(()=>node.classList.remove('rrUnreadFocus71'),4000);};requestAnimationFrame(()=>requestAnimationFrame(position));setTimeout(position,180);return true;
 }
 window.RRStaffUnread71={refresh,prepare,rows,apply};
 let scheduled=false;new MutationObserver(()=>{if(scheduled)return;scheduled=true;requestAnimationFrame(()=>{scheduled=false;paint()})}).observe(document.body,{childList:true,subtree:true});
 setInterval(()=>{if(!document.hidden)refresh()},3000);document.addEventListener('visibilitychange',()=>{if(!document.hidden)refresh()});
})();
