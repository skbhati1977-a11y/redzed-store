(()=>{'use strict';
 async function boot(){
  const anchor=document.getElementById('msg');if(!anchor||!window.RF853||RF853.mode()!=='TEST')return;
  try{const d=await RF853.rpc('rr_rm_chat_fast_queue_test71',{p_status:'WORKING'});if(!d.can_complete_mapping)return;
   const count=(d.cards||[]).filter(c=>!c.market_ready).length;
   const a=document.createElement('a');a.textContent='Readymade mapping / approval pending · '+count+' · Complete in Working';
   const url=new URL('test70-cb-purchase-real-chat-pilot.html',location.href);url.searchParams.set('rc_view','chat');url.searchParams.set('rc_kind','group');url.searchParams.set('rc_id','READYMADE');url.searchParams.set('rc_status','WORKING');url.searchParams.set('rm_mapping','PENDING');a.href=url.href;a.style.cssText='display:block;padding:12px;margin:10px 0;border:1px solid #45617c;border-radius:10px;color:#b7d5f3';anchor.after(a);
  }catch(e){console.warn('Readymade pending queue unavailable',e)}
 }
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
