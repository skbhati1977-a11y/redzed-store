(()=>{'use strict';
 if(window.__RRInboxSummary71)return;window.__RRInboxSummary71=true;
 let data=[],busy=false;
 const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 function paint(){
  const host=document.getElementById('rows');if(!host)return;
  const pending=Number(window.RRAdminLoginApprovals71?.pendingCount()||0);
  let badge=document.getElementById('rrApprovalBadge71');const admin=document.querySelector('[data-department="ADMIN"] b');
  if(admin&&pending){if(!badge){badge=document.createElement('span');badge.id='rrApprovalBadge71';admin.appendChild(badge)}badge.textContent=' · '+pending+' login approvals';}else badge?.remove();
  let panel=document.getElementById('rrInboxSummary71');if(!panel){panel=document.createElement('section');panel.id='rrInboxSummary71';panel.style.cssText='padding:12px;border-bottom:1px solid #294159';host.before(panel)}
  const unread=data.filter(x=>Number(x.unread_count)>0),total=unread.reduce((n,x)=>n+Number(x.unread_count),0);
  const html='<b>Unread messages: '+total+' · Chats: '+unread.length+'</b>'+ (pending?'<p>Admin · '+pending+' pending login approvals</p>':'')+unread.map(x=>'<a class="row" href="real-sales-live-chat-v9434.html?chat='+encodeURIComponent(x.chat_id)+'"><span>'+esc(x.customer_name||x.chat_name||x.title||'Customer chat')+'</span><strong style="margin-left:auto;border-radius:20px;background:#2376cf;padding:4px 10px">'+Number(x.unread_count)+'</strong></a>').join('');
  if(panel.innerHTML!==html)panel.innerHTML=html;
 }
 async function refresh(){if(busy||!window.RF853?.rpc)return;busy=true;try{const result=await RF853.rpc('rr_chat_staff_inbox_v61');data=Array.isArray(result)?result:[];paint()}catch(e){console.warn('Chat unread counts unavailable',e)}finally{busy=false}}
 setInterval(()=>{if(!document.hidden){paint();refresh()}},3000);document.addEventListener('visibilitychange',()=>{if(!document.hidden)refresh()});setTimeout(refresh,1000);
})();
